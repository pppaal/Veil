// The frame around the conversations: the signed-in identity in the
// sidebar, the connection pill, the private-beta banner and the banner for
// an identity from before protocol v2.

import { isLegacyIdentity } from '../../crypto/identity.js';
import { $, avatarFor, el } from '../dom.js';

const BETA_BANNER_HEIGHT_PX = 38;

// preferences: src/app/services/preferences.js.
export function createAppShell({ store, preferences }) {
  const { state } = store;

  function renderMe() {
    if (!state.me) return;
    $('sidebar-me').replaceChildren(
      avatarFor(state.me.handle, 'sm'),
      el('div', {}, [
        el('div', { style: 'font-weight:600' }, ['@' + state.me.handle]),
        el('div', { style: 'font-size:11px;color:var(--fg-faint)' }, ['기기 ' + state.me.deviceId.slice(0, 8)]),
      ]),
    );
  }

  // The CSS variable --banner-h moves the app and auth screen down, so the
  // banner never covers the composer.
  function setBetaBannerVisible(show) {
    const banner = $('beta-banner');
    if (!banner) return;
    banner.classList.toggle('hidden', !show);
    document.documentElement.style.setProperty('--banner-h', show ? BETA_BANNER_HEIGHT_PX + 'px' : '0px');
  }

  function setConnection(kind, text) {
    const pill = $('conn-pill');
    pill.className = 'topbar-pill ' + kind;
    pill.textContent = text;
    pill.classList.remove('is-disconnected', 'is-connecting');
    if (kind === 'connecting' || kind === 'offline') pill.classList.add('is-connecting');
    if (kind === 'error' || kind === 'disconnected') pill.classList.add('is-disconnected');
  }

  return {
    // The saved theme applies before anything renders.
    applyTheme() {
      if (preferences.lightTheme()) document.documentElement.classList.add('theme-light');
    },

    // Visible until dismissed, once per device.
    mountBetaBanner() {
      const close = $('beta-banner-close');
      if (!$('beta-banner') || !close) return;
      setBetaBannerVisible(!preferences.betaBannerDismissed());
      close.addEventListener('click', () => {
        setBetaBannerVisible(false);
        preferences.dismissBetaBanner();
      });
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

    // kind: 'connected', 'connecting', 'offline', 'error' or 'disconnected';
    // a stuck connection gets a colour as well as the text.
    setConnection,

    // Back to the signed-out frame once the session's state is dropped.
    reset() {
      setConnection('offline', '오프라인');
      $('app').classList.remove('viewing-chat');
    },

    // The reconnect attempt the socket is backing off from, or null.
    setRetry(attempt) {
      const pill = $('conn-pill');
      let badge = pill?.querySelector('.retry-count');
      if (attempt === null) {
        badge?.remove();
        return;
      }
      if (!pill) return;
      if (!badge) {
        badge = el('span', { class: 'retry-count' });
        pill.appendChild(badge);
      }
      badge.textContent = `(${attempt})`;
    },
  };
}
