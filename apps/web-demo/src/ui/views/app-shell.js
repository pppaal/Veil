// The frame around the conversations: the bar's title with the connection
// state under it (shown only while there is no live connection), the
// signed-in account at the top of the menu, and the banner for an account
// from before protocol v2.

import { t } from '../../../i18n/i18n.js';
import { isLegacyIdentity } from '../../crypto/identity.js';
import { $, avatarFor, el, iconButton } from '../dom.js';
import { shortcutLabel } from '../keys.js';

// What the bar says for each connection state; a live one says nothing.
const CONNECTION_TEXT_KEYS = { connecting: 'shell.connecting', offline: 'shell.offline' };

export function createAppShell({ store }) {
  const { state } = store;
  let status = 'offline';

  // The menu's header: who is signed in, and a button to copy the handle
  // (the menu's copy-handle action).
  function renderMe() {
    if (!state.me) return;
    $('menu-me').replaceChildren(
      avatarFor(state.me.handle, 'sm'),
      el('div', { class: 'menu-me-handle' }, ['@' + state.me.handle]),
      iconButton('copy', t('menu.copyHandle'), { class: 'icon-btn menu-me-copy', dataset: { action: 'copy-handle' }, role: 'menuitem' }),
    );
  }

  function renderConnection() {
    const node = $('conn-status');
    if (!node) return;
    const connected = status === 'connected';
    node.className = `conn-status ${status}${connected ? ' hidden' : ''}`;
    node.textContent = connected ? '' : t(CONNECTION_TEXT_KEYS[status] ?? 'shell.offline');
  }

  // kind: 'connected', 'connecting' or 'offline'.
  function setConnection(kind) {
    status = kind;
    renderConnection();
  }

  // The bar's buttons: their names, and the new chat shortcut as this
  // platform writes it.
  function labelBar() {
    const newChat = $('new-chat-btn');
    newChat.title = t('shell.newChatTooltip', { shortcut: shortcutLabel('N') });
    newChat.setAttribute('aria-label', t('newChat.title'));
    $('split-btn').title = t('shell.splitView');
    $('split-btn').setAttribute('aria-label', t('shell.splitView'));
  }

  return {
    show() {
      labelBar();
      $('auth-screen').classList.add('hidden');
      $('app').classList.remove('hidden');
      // An account from before protocol v2 can read what it has but can
      // never send again (src/crypto/identity.js): offer to replace it.
      $('legacy-banner').classList.toggle('hidden', !isLegacyIdentity(state.me));
      renderMe();
      store.notify('sidebar', 'panels');
    },

    setConnection,

    // Back to the signed-out frame once the session's state is dropped.
    reset() {
      setConnection('offline');
      $('app').classList.remove('viewing-chat');
    },
  };
}
