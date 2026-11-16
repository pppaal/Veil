// One-time secret page. Compose mode seals a secret and prints the link;
// view mode (a fragment is present) waits for the recipient to press Reveal
// before fetching, because the fetch burns the secret on the server and link
// unfurlers and prefetchers execute pages without anyone reading them.

import {
  formatSecretFragment,
  openSecret,
  parseSecretFragment,
  sealSecret,
} from './src/crypto/secret-link.js';

const API = '/v1';

// The page's words. They live here and in s.html because a production
// server serves only this page and its modules (apps/api/src/web-assets.ts
// SECRET_VIEWER_FILES), not i18n/en.json.
const TEXT = Object.freeze({
  cantOpen: "This link can't be opened",
  gone: 'This link was already opened, or it expired.',
  wrongPassphrase: "Couldn't open it. Check the passphrase and try again. If you close this page, it can't be opened again.",
  invalid: "This link isn't valid.",
  // The compose field's word for what was sent.
  revealed: 'Secret',
  createFailed: "Couldn't create the link. Try again.",
  createLink: 'Create link',
  copied: 'Copied',
  copyFailed: "Couldn't copy. Select the link and copy it.",
});
const $ = (id) => document.getElementById(id);
const setVisible = (id, visible) => { $(id).hidden = !visible; };

const fragment = location.hash.slice(1);
if (fragment) mountViewer(fragment);
else mountComposer();

function mountViewer(rawFragment) {
  setVisible('view', true);
  const link = parseSecretFragment(rawFragment);
  if (!link) {
    showGone(TEXT.cantOpen);
    return;
  }
  setVisible('passPrompt', link.needsPassphrase);
  let blob = null;

  $('revealBtn').addEventListener('click', async () => {
    const passphrase = link.needsPassphrase ? $('passIn').value : '';
    if (link.needsPassphrase && !passphrase) {
      $('passIn').focus();
      return;
    }
    $('revealBtn').disabled = true;
    setVisible('vErr', false);
    try {
      blob ??= await burnAndFetch(link.id);
    } catch {
      showGone(TEXT.gone);
      return;
    }
    try {
      const text = await openSecret(crypto, blob, link, passphrase);
      showSecret(text);
    } catch {
      // The server copy is gone, but the blob stays in memory so a mistyped
      // passphrase can be retried on this page.
      $('vErr').textContent = link.needsPassphrase ? TEXT.wrongPassphrase : TEXT.invalid;
      setVisible('vErr', true);
      $('revealBtn').disabled = !link.needsPassphrase;
    }
  });
}

async function burnAndFetch(id) {
  const response = await fetch(`${API}/s/${encodeURIComponent(id)}`);
  if (response.status !== 200) throw new Error('gone');
  return (await response.json()).ciphertext;
}

function showSecret(text) {
  setVisible('revealPanel', false);
  $('viewTitle').textContent = TEXT.revealed;
  $('revealText').textContent = text;
  setVisible('revealWrap', true);
  // The key has done its job; keep it out of the address bar and history.
  history.replaceState(null, '', location.pathname + location.search);
}

function showGone(message) {
  setVisible('revealPanel', false);
  $('viewTitle').textContent = '';
  $('goneMsg').textContent = message;
  setVisible('gone', true);
}

function mountComposer() {
  setVisible('compose', true);
  $('usePass').addEventListener('change', (event) => setVisible('passWrap', event.target.checked));
  let lastLink = '';

  $('genBtn').addEventListener('click', async () => {
    setVisible('cErr', false);
    const secret = $('secret').value.trim();
    if (!secret) {
      $('secret').focus();
      return;
    }
    const usePassphrase = $('usePass').checked;
    const passphrase = usePassphrase ? $('pass').value : '';
    if (usePassphrase && !passphrase) {
      $('pass').focus();
      return;
    }
    const button = $('genBtn');
    button.disabled = true;
    button.replaceChildren(Object.assign(document.createElement('span'), { className: 'spin' }));
    try {
      const { blob, fragmentSecret } = await sealSecret(crypto, secret, passphrase);
      const response = await fetch(`${API}/s`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ciphertext: blob }),
      });
      if (!response.ok) throw new Error('server');
      const { id } = await response.json();
      lastLink = `${location.origin}${location.pathname}#${formatSecretFragment(id, fragmentSecret)}`;
      $('linkText').textContent = lastLink;
      setVisible('out', true);
      setVisible('passApart', usePassphrase);
      $('copied').textContent = '';
    } catch {
      $('cErr').textContent = TEXT.createFailed;
      setVisible('cErr', true);
    } finally {
      button.disabled = false;
      button.textContent = TEXT.createLink;
    }
  });

  $('copyBtn').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(lastLink);
      $('copied').textContent = TEXT.copied;
    } catch {
      $('copied').textContent = TEXT.copyFailed;
    }
  });
}
