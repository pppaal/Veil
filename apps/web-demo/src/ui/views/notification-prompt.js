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
    const enable = el('button', { class: 'enable' }, ['Turn on']);
    const later = el('button', { class: 'dismiss' }, ['Later']);
    const node = el('div', { class: 'notif-prompt' }, [
      el('span', { style: 'flex:1;line-height:1.4' }, [
        'Turn on notifications?',
        el('br'),
        el('span', { style: 'opacity:0.7;font-size:11px' }, ['You will be told about new messages while this tab is in the background.']),
      ]),
      enable,
      later,
    ]);
    enable.addEventListener('click', async () => {
      try {
        const result = await Notification.requestPermission();
        toast(result === 'granted' ? 'Notifications on' : 'Notifications blocked', result === 'granted' ? 'good' : 'error');
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
