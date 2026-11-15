// The offer to turn on browser notifications, at the top of the sidebar
// once signed in, until the user answers or dismisses it.

import { el, icon } from '../dom.js';
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
    const enable = el('button', { class: 'text-btn enable' }, ['Turn on']);
    const later = el('button', { class: 'text-btn dismiss' }, ['Later']);
    const node = el('div', { class: 'notice notif-prompt', role: 'region', 'aria-label': 'Notifications' }, [
      icon('bell', 'notice-icon tone-info'),
      el('div', { class: 'notice-text' }, [
        el('div', { class: 'notice-title' }, ['Turn on notifications?']),
        el('div', { class: 'notice-body' }, ['You will be told about new messages while this tab is in the background.']),
      ]),
      el('div', { class: 'notice-actions' }, [later, enable]),
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
