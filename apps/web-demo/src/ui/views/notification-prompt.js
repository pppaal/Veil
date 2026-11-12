// The offer to turn on browser notifications, at the top of the sidebar
// once signed in, until the user answers or dismisses it.

import { el } from '../dom.js';
import { toast } from '../toast.js';

const CHECK_MS = 2000;

// preferences: src/app/services/preferences.js.
export function createNotificationPrompt({ store, preferences }) {
  let dismissed = preferences.notificationPromptDismissed();

  function offer() {
    if (dismissed) return;
    if (!('Notification' in window)) return;
    if (Notification.permission !== 'default') return;
    if (preferences.notificationLevel() === 'off') return;
    if (!store.state.me) return;
    if (document.querySelector('.notif-prompt')) return;
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;
    const enable = el('button', { class: 'enable' }, ['켜기']);
    const later = el('button', { class: 'dismiss' }, ['나중에']);
    const node = el('div', { class: 'notif-prompt' }, [
      el('span', { style: 'flex:1;line-height:1.4' }, [
        '알림 켤까요?',
        el('br'),
        el('span', { style: 'opacity:0.7;font-size:11px' }, ['백그라운드에서도 새 메시지를 알려요.']),
      ]),
      enable,
      later,
    ]);
    enable.addEventListener('click', async () => {
      try {
        const result = await Notification.requestPermission();
        toast(result === 'granted' ? '알림 켜짐' : '알림 거부됨', result === 'granted' ? 'good' : 'error');
      } catch {}
      node.remove();
    });
    later.addEventListener('click', () => {
      dismissed = true;
      preferences.dismissNotificationPrompt();
      node.remove();
    });
    sidebar.insertBefore(node, sidebar.firstChild);
  }

  return {
    // Checked every couple of seconds: sign-in and permission changes
    // decide when it shows.
    mount() {
      setInterval(offer, CHECK_MS);
    },
  };
}
