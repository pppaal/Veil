// What the conversation list, tabs and panel headers derive from a
// conversation summary (GET /conversations) and the messages loaded for it.

import { isGone, isShown, previewLabel } from './ingest.js';

// The other member of a direct conversation, the one sessions, pins and
// safety numbers are about. Without our own userId the "other" member could
// be ourselves, and an envelope sealed to our own key reaches nobody, so
// there is no peer until a login has named us. A group has no single peer:
// sealing to, or pinning, any one member would be wrong.
export function directPeer(conversation, selfUserId) {
  if (!selfUserId || conversation?.type !== 'direct') return null;
  return conversation.members?.find((member) => member.userId !== selfUserId) ?? null;
}

// The member a conversation row, tab and panel header are named after.
export function shownPeer(conversation, selfHandle) {
  return (conversation.members || []).find((member) => member.handle !== selfHandle) ?? conversation.members?.[0];
}

// Newest activity first: the last message, or the creation of a
// conversation that has none.
export function byLastActivity(a, b) {
  const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
  const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
  return bx.localeCompare(ax);
}

// Whether a member's handle contains the sidebar search query.
export function matchesSearch(conversation, query) {
  if (!query) return true;
  return (conversation.members || []).some((member) => (member.handle || '').toLowerCase().includes(query));
}

// The message a conversation row previews: its latest one a panel shows.
// The relay's last message may be gone (expired, or deleted from this
// device's history) or a reaction, which is no bubble of its own; then the
// loaded history stands in, and a reaction's label only when nothing does.
export function previewMessage(conversation, loaded, now) {
  const last = conversation.lastMessage;
  if (last && isShown(last, now)) return last;
  const shown = loaded.findLast((message) => isShown(message, now));
  return shown ?? (last && !isGone(last, now) ? last : null);
}

// A message's preview label cut to maxChars, for reply quotes.
export function snippetOf(message, maxChars) {
  const text = previewLabel(message);
  return text.length > maxChars ? text.slice(0, maxChars) + '…' : text;
}
