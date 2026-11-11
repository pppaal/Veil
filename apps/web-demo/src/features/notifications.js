// OS notification privacy levels. Whatever a notification shows is written
// into persistent OS stores (macOS Notification Center, Windows Action
// Center) outside VEIL's control, so the default matches mobile push: a
// generic "new message" with no sender and no content.
//   off             no notification
//   generic         app name + "new message"            (default)
//   sender          sender handle + "new message"
//   sender_preview  sender handle + text or kind label

export const NOTIFICATION_LEVELS = Object.freeze(['off', 'generic', 'sender', 'sender_preview']);
export const DEFAULT_NOTIFICATION_LEVEL = 'generic';
export const NOTIFICATION_LEVEL_KEY = 'veil-demo-notification-level-v1';

const DEFAULT_LABELS = Object.freeze({ appName: 'VEIL', newMessage: 'New message' });

export function readNotificationLevel(storage) {
  try {
    const stored = storage?.getItem(NOTIFICATION_LEVEL_KEY);
    return NOTIFICATION_LEVELS.includes(stored) ? stored : DEFAULT_NOTIFICATION_LEVEL;
  } catch {
    return DEFAULT_NOTIFICATION_LEVEL;
  }
}

export function writeNotificationLevel(storage, level) {
  if (!NOTIFICATION_LEVELS.includes(level)) return false;
  try {
    storage.setItem(NOTIFICATION_LEVEL_KEY, level);
    return true;
  } catch {
    return false;
  }
}

// Returns { title, body, tag } or null when nothing should be shown.
// preview is the message's previewLabel(), already free of payload data.
export function buildNotification({ level, senderHandle, preview, conversationId, labels = DEFAULT_LABELS }) {
  const named = senderHandle ? `@${senderHandle}` : labels.appName;
  switch (level) {
    case 'off':
      return null;
    case 'sender':
      return { title: named, body: labels.newMessage, tag: `veil-${conversationId}` };
    case 'sender_preview':
      return { title: named, body: preview || labels.newMessage, tag: `veil-${conversationId}` };
    default:
      // One shared tag: conversation ids stay out of the OS store too.
      return { title: labels.appName, body: labels.newMessage, tag: 'veil' };
  }
}
