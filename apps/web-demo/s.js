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
const $ = (id) => document.getElementById(id);
const setVisible = (id, visible) => { $(id).style.display = visible ? 'block' : 'none'; };

const fragment = location.hash.slice(1);
if (fragment) mountViewer(fragment);
else mountComposer();

function mountViewer(rawFragment) {
  setVisible('view', true);
  const link = parseSecretFragment(rawFragment);
  if (!link) {
    showGone('열 수 없는 링크입니다');
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
      showGone('이미 열렸거나 만료된 링크입니다');
      return;
    }
    try {
      const text = await openSecret(crypto, blob, link, passphrase);
      showSecret(text);
    } catch {
      // The server copy is gone, but the blob stays in memory so a mistyped
      // passphrase can be retried on this page.
      $('vErr').textContent = link.needsPassphrase
        ? '복호화 실패 — 암호문구를 다시 확인하세요. 이 페이지를 닫으면 다시 열 수 없습니다.'
        : '복호화 실패 — 잘못된 링크입니다.';
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
  $('viewTitle').textContent = '비밀 메시지';
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
      $('copied').textContent = '';
    } catch {
      $('cErr').textContent = '링크 생성 실패 — 잠시 후 다시 시도하세요.';
      setVisible('cErr', true);
    } finally {
      button.disabled = false;
      button.textContent = '보안 링크 생성';
    }
  });

  $('copyBtn').addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(lastLink);
      $('copied').textContent = '복사됨 ✓';
    } catch {
      $('copied').textContent = '수동 복사하세요';
    }
  });
}
