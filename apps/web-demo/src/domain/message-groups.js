// How a conversation panel lays out its messages: by day, and within a day
// in runs from one device, and what an own message's delivery state shows.

// Consecutive messages from one device within this gap form one group.
export const GROUP_GAP_MS = 2 * 60 * 1000;

// When a message was sent, as the panel orders and labels it: the server's
// time, or the local time of a send it has not acknowledged yet.
export const sentAt = (message, fallback) => new Date(message.serverReceivedAt || message._localAt || fallback);

// [{ dayKey, dayLabel, groups: [{ senderDeviceId, senderHandle, isMe, msgs }] }]
// in the order of `messages`. Every device that is not ours is shown under
// peerHandle: a direct conversation has no one else.
export function groupMessages(messages, { me, peerHandle, dayKey, dayLabel, now = Date.now() }) {
  const days = [];
  let day = null;
  let group = null;
  for (const message of messages) {
    const at = sentAt(message, now);
    const key = dayKey(at);
    if (!day || day.dayKey !== key) {
      day = { dayKey: key, dayLabel: dayLabel(at), groups: [] };
      days.push(day);
      group = null;
    }
    const isMe = message.senderDeviceId === me.deviceId;
    const last = group?.msgs.at(-1);
    if (group && group.senderDeviceId === message.senderDeviceId && at - sentAt(last, 0) < GROUP_GAP_MS) {
      group.msgs.push(message);
    } else {
      group = { senderDeviceId: message.senderDeviceId, senderHandle: isMe ? me.handle : peerHandle || '?', isMe, msgs: [message] };
      day.groups.push(group);
    }
  }
  return days;
}

// The delivery state of an own message: 'pending', 'failed', 'read',
// 'delivered' or 'sent'.
export function deliveryStatus(message) {
  if (message._status === 'pending') return 'pending';
  if (message._status === 'failed') return 'failed';
  if (message.readAt) return 'read';
  if (message.deliveredAt) return 'delivered';
  return 'sent';
}

export const DELIVERY_GLYPHS = Object.freeze({
  pending: '⏳',
  failed: '!',
  read: '✓✓',
  delivered: '✓✓',
  sent: '✓',
});

export const DELIVERY_LABELS = Object.freeze({
  pending: '전송 중',
  failed: '전송 실패',
  read: '읽음',
  delivered: '전달됨',
  sent: '전송됨',
});
