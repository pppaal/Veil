// The chat header's ⋮ menu: mute (for a set time or for good) or unmute,
// then report, block and clearing this browser's copy of the chat, the last
// two in red. Report and block need the one other member of a direct chat.

import { t } from '../../../i18n/i18n.js';
import { shownHandle } from '../../domain/handles.js';
import { el } from '../dom.js';

// The mute choices, the same as the mobile app's.
const MUTE_CHOICES = [
  ['mute.oneHour', 3600],
  ['mute.eightHours', 8 * 3600],
  ['mute.oneWeek', 7 * 86400],
  ['mute.always', 'always'],
];

// safety: src/app/services/safety.js; reportDialog:
// src/ui/views/report-dialog.js; confirm: src/ui/confirm.js;
// clearHistory(convId): the chat view's local history delete.
export function createChatMenu({ store, safety, reportDialog, confirm, clearHistory }) {
  let menu = null;

  // A redraw of the panel rebuilds the header, not this menu: it stays open
  // until a click lands outside it (or on an item), Esc, or a resize.
  function close() {
    menu?.remove();
    menu = null;
    document.removeEventListener('click', onOutside, true);
    window.removeEventListener('resize', close);
  }

  // A click on a ⋮ button (a redraw may have replaced the one that opened
  // it) is left to open(), which toggles.
  function onOutside(event) {
    if (!menu || menu.contains(event.target) || event.target.closest?.('.chat-menu-btn')) return;
    close();
  }

  async function block(peer) {
    const handle = shownHandle(peer.handle);
    const ok = await confirm({
      title: t('safety.blockTitle', { handle }),
      body: t('safety.blockBody'),
      okLabel: t('safety.blockConfirm'),
      destructive: true,
    });
    if (ok) await safety.block(peer.userId, handle);
  }

  // An item; the menu closes before its action runs.
  const item = (label, action, { danger = false, keepOpen = false } = {}) => el('button', {
    class: danger ? 'menu-item menu-danger' : 'menu-item',
    role: 'menuitem',
    onclick: (event) => {
      event.stopPropagation();
      if (!keepOpen) close();
      action();
    },
  }, [label]);
  const separator = () => el('div', { class: 'menu-sep' });

  function showMuteChoices(convId) {
    menu.replaceChildren(...MUTE_CHOICES.map(([key, duration]) => item(t(key), () => safety.setMute(convId, duration))));
    menu.querySelector('button')?.focus();
  }

  function items(convId, peer) {
    const muted = store.isMuted(convId);
    return [
      muted
        ? item(t('mute.unmute'), () => safety.setMute(convId, null))
        : item(t('mute.title'), () => showMuteChoices(convId), { keepOpen: true }),
      separator(),
      ...(peer
        ? [
          item(t('chat.report'), () => reportDialog.open(convId, null, peer)),
          item(t('chat.block'), () => block(peer), { danger: true }),
        ]
        : []),
      item(t('chat.clear'), () => clearHistory(convId), { danger: true }),
    ];
  }

  return {
    // Opens under `button` for the conversation; peer: the other member of
    // a direct chat, or null.
    open(button, convId, peer) {
      const wasOpenHere = Boolean(menu && !menu.classList.contains('hidden') && menu.dataset.conv === convId);
      close();
      if (wasOpenHere) return;
      const rect = button.getBoundingClientRect();
      menu = el('div', { class: 'menu chat-menu', role: 'menu', dataset: { conv: convId } }, items(convId, peer));
      menu.style.top = `${Math.round(rect.bottom + 4)}px`;
      menu.style.right = `${Math.max(4, Math.round(window.innerWidth - rect.right))}px`;
      document.body.appendChild(menu);
      document.addEventListener('click', onOutside, true);
      window.addEventListener('resize', close);
    },

    close,
  };
}
