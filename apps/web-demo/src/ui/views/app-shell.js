// The frame around the conversations: the signed-in identity in the
// sidebar, the connection state after the title in the bar (shown only
// while there is no live connection), and the banner for an identity from
// before protocol v2.

import { isLegacyIdentity } from '../../crypto/identity.js';
import { $, applyThemeClass, avatarFor, el } from '../dom.js';

// preferences: src/app/services/preferences.js.
export function createAppShell({ store, preferences }) {
  const { state } = store;
  let status = { kind: 'offline', text: '' };

  function renderMe() {
    if (!state.me) return;
    $('sidebar-me').replaceChildren(
      avatarFor(state.me.handle, 'sm'),
      el('div', { class: 'sidebar-me-handle' }, ['@' + state.me.handle]),
    );
  }

  // A live connection says nothing; anything else says what it is.
  function renderConnection() {
    const node = $('conn-status');
    if (!node) return;
    const connected = status.kind === 'connected';
    node.className = `conn-status ${status.kind}${connected ? ' hidden' : ''}`;
    node.textContent = connected ? '' : status.text;
  }

  // kind: 'connected', 'connecting', 'offline', 'error' or 'disconnected'.
  function setConnection(kind, text) {
    status = { kind, text };
    renderConnection();
  }

  return {
    // The saved theme applies before anything renders.
    applyTheme() {
      applyThemeClass(preferences.lightTheme());
    },

    show() {
      $('auth-screen').classList.add('hidden');
      $('app').classList.remove('hidden');
      // An identity from before protocol v2 can read what it has but can
      // never send again (src/crypto/identity.js): offer to replace it.
      $('legacy-banner').classList.toggle('hidden', !isLegacyIdentity(state.me));
      renderMe();
      store.notify('sidebar', 'panels');
    },

    setConnection,

    // Back to the signed-out frame once the session's state is dropped.
    reset() {
      setConnection('offline', 'Offline');
      $('app').classList.remove('viewing-chat');
    },
  };
}
