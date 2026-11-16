// The offer to turn on browser notifications, above the chat list, once
// the user has sent a message, until they answer it or say not now.

import { t } from '../../../i18n/i18n.js';
import { el, icon } from '../dom.js';
import { toast } from '../toast.js';

const CHECK_MS = 2000;

// preferences: src/app/services/preferences.js.
export function createNotificationPrompt({ store, preferences }) {
  const { state } = store;
  let dismissed = preferences.notificationPromptDismissed();

  // Asked after a first message, not at sign-in: by then the user knows
  // what the notifications would be for.
  const hasSent = () => [...state.messagesByConv.values()].some((list) => list.some((message) => message.senderDeviceId === state.me.deviceId));

  function offer() {
    if (dismissed) return;
    if (!('Notification' in window)) return;
    if (Notification.permission !== 'default') return;
    if (preferences.notificationLevel() === 'off') return;
    if (!state.me) return;
    if (document.querySelector('.notif-prompt')) return;
    const sidebar = document.getElementById('sidebar');
    if (!sidebar || !hasSent()) return;
    const enable = el('button', { class: 'text-btn enable' }, [t('notifyPrompt.turnOn')]);
    const later = el('button', { class: 'text-btn dismiss' }, [t('notifyPrompt.later')]);
    const node = el('div', { class: 'notice notif-prompt', role: 'region', 'aria-label': t('settings.section.notifications') }, [
      icon('bell', 'notice-icon tone-info'),
      el('div', { class: 'notice-text' }, [
        el('div', { class: 'notice-title' }, [t('notifyPrompt.title')]),
        el('div', { class: 'notice-body' }, [t('notifyPrompt.body')]),
      ]),
      el('div', { class: 'notice-actions' }, [later, enable]),
    ]);
    enable.addEventListener('click', async () => {
      try {
        const result = await Notification.requestPermission();
        toast(t(result === 'granted' ? 'notifications.on' : 'notifications.denied'), result === 'granted' ? 'good' : 'error');
      } catch {}
      node.remove();
    });
    later.addEventListener('click', () => {
      dismissed = true;
      preferences.dismissNotificationPrompt();
      node.remove();
      toast(t('notifyPrompt.dismissed'));
    });
    sidebar.insertBefore(node, sidebar.firstChild);
  }

  return {
    // Checked every couple of seconds: a first send and permission changes
    // decide when it shows.
    mount() {
      setInterval(offer, CHECK_MS);
    },
  };
}
