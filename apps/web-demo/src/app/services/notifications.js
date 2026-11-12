// Telling the user about messages while the tab is hidden: an unread count
// in the tab title and, with permission, an OS notification whose content
// follows the notification privacy level (src/features/notifications.js).

import { t } from '../../../i18n/i18n.js';
import { previewLabel } from '../../domain/ingest.js';
import { buildNotification } from '../../features/notifications.js';

// preferences: src/app/services/preferences.js; peerOf(convId) -> member.
export function createNotifications({ store, preferences, peerOf }) {
  let unread = 0;

  function updateTitle() {
    const base = document.title.replace(/^\(\d+\)\s*/, '');
    document.title = unread > 0 ? `(${unread}) ${base}` : 'VEIL';
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    unread = 0;
    updateTitle();
  });

  return {
    bumpUnread() {
      if (document.visibilityState === 'visible') return;
      unread += 1;
      updateTitle();
    },

    // The body is the message's preview label, never its payload.
    show(message) {
      if (document.visibilityState === 'visible') return;
      if (!('Notification' in window)) return;
      if (Notification.permission !== 'granted') return;
      if (store.state.muted.has(message.conversationId)) return;
      const content = buildNotification({
        level: preferences.notificationLevel(),
        senderHandle: peerOf(message.conversationId)?.handle,
        preview: previewLabel(message),
        conversationId: message.conversationId,
        labels: { appName: 'VEIL', newMessage: t('notifications.newMessage') },
      });
      if (!content) return;
      try {
        const notification = new Notification(content.title, { body: content.body, icon: './icon.svg', tag: content.tag, silent: false });
        notification.onclick = () => {
          window.focus();
          if (message.conversationId) store.state.activeConv = message.conversationId;
          try {
            notification.close();
          } catch {}
          store.notify('panels');
        };
      } catch {}
    },
  };
}
