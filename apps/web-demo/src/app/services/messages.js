// The in-memory message views and their cached envelopes. Every path that
// turns a server envelope into a displayed message comes through ingest,
// and content comes from the decrypt-once store
// (src/features/secure-messaging.js). Only envelopes are cached
// (src/platform/persist.js); views are rebuilt through the same ingest path.

import { byLastActivity } from '../../domain/conversations.js';
import { ingestMessage } from '../../domain/ingest.js';
import { isPendingId, pendingId } from '../../domain/local-messages.js';
import { messageCacheRecord, serializeConversationForCache } from '../../platform/persist.js';

// Receipts change after delivery and are never cached, so they ride on the
// in-memory message next to its view.
const RECEIPT_FIELDS = ['clientMessageId', 'deliveredAt', 'readAt', 'editCount'];
// Blob URLs and load failures belong to a media handle; a reused view keeps them.
const MEDIA_STATE_FIELDS = ['_imageUrl', '_voiceUrl', '_mediaFailed'];

// The blob: URLs a message's media was materialized to. They hold the
// decrypted bytes for the page's lifetime unless revoked.
const blobUrlsOf = (message) =>
  [message?._voiceUrl, message?._imageUrl].filter((url) => typeof url === 'string' && url.startsWith('blob:'));

export function createMessages({ store, stack }) {
  const { state } = store;
  // The newest re-ingest started for each message. Re-ingests race: our own
  // edit's echo from the relay can start opening the old stored content
  // before the edit is remembered and finish after the edit's own re-ingest,
  // so only the most recently started one may write its view.
  let reingestSeq = 0;
  const latestReingest = new Map();

  // `content` is passed only for our own sends, whose content we already hold.
  // That content is authoritative, so no earlier view is reused for it: our
  // own edit's echo from the relay can arrive before the edit is stored and
  // leave a view with the new ciphertext but the old text.
  async function ingest(raw, { previous = null, content } = {}) {
    const open = content === undefined ? (envelope) => stack.secure.open(envelope) : async () => ({ content });
    const view = await ingestMessage(raw, {
      open,
      retire: (envelope) => stack.secure.retire(envelope),
      media: stack.media,
      previous: content === undefined ? previous : null,
    });
    if (previous && view.media !== null && view.media === previous.media) {
      for (const field of MEDIA_STATE_FIELDS) if (previous[field] !== undefined) view[field] = previous[field];
    }
    for (const field of RECEIPT_FIELDS) {
      const value = raw[field] ?? previous?.[field];
      if (value !== undefined) view[field] = value;
    }
    return view;
  }

  function revokeBlobUrls(message) {
    for (const url of blobUrlsOf(message)) {
      try {
        URL.revokeObjectURL(url);
      } catch {}
    }
    if (message) {
      message._voiceUrl = null;
      message._imageUrl = null;
    }
  }

  async function persistConversation(conv) {
    try {
      await stack.identityDb.put('conversations', serializeConversationForCache(conv));
    } catch {}
  }

  async function persistMessage(message) {
    if (!message.id || !message.conversationId || isPendingId(message.id)) return;
    const record = messageCacheRecord(message);
    // An expired message leaves the device altogether, its envelope included.
    try {
      if (message.kind === 'expired') await stack.identityDb.delete('messages', record._key);
      else await stack.identityDb.put('messages', record);
    } catch {}
  }

  return {
    ingest,
    revokeBlobUrls,

    // Replaces a conversation's message list and frees blob URLs that no
    // remaining message uses.
    setMessages(convId, next) {
      const live = new Set(next.flatMap(blobUrlsOf));
      for (const message of store.messagesOf(convId)) {
        for (const url of blobUrlsOf(message)) if (!live.has(url)) URL.revokeObjectURL(url);
      }
      state.messagesByConv.set(convId, next);
    },

    revokeAllBlobUrls() {
      for (const list of state.messagesByConv.values()) for (const message of list) revokeBlobUrls(message);
    },

    sortConversations() {
      state.conversations.sort(byLastActivity);
    },

    persistConversation,
    async persistAllConversations() {
      for (const conv of state.conversations) await persistConversation(conv);
    },
    persistMessage,
    async persistMessages(list) {
      for (const message of list) await persistMessage(message);
    },
    // Drops a message's cached envelope.
    uncache: (message) => stack.identityDb.delete('messages', messageCacheRecord(message)._key),

    // Re-ingests a changed envelope (edit, tombstone) and swaps the result in
    // wherever the old view is shown.
    async reingestInPlace(messageId, raw, { content, editCount } = {}) {
      const ticket = ++reingestSeq;
      latestReingest.set(messageId, ticket);
      const previous = store.locateMessage(messageId)?.message ?? null;
      const view = await ingest(raw, { previous, content });
      if (latestReingest.get(messageId) !== ticket) return;
      latestReingest.delete(messageId);
      if (editCount !== undefined) view.editCount = editCount;
      const current = store.locateMessage(messageId);
      if (!current) return;
      current.list[current.index] = view;
      const conv = store.conversation(current.convId);
      if (conv?.lastMessage?.id === messageId) conv.lastMessage = view;
      persistMessage(view);
      store.notify('sidebar');
      if (store.isOnScreen(current.convId)) store.notify('panels');
    },

    // Own message that exists only locally until its upload and send finish.
    pendingLocalMessage({ clientMessageId, conversationId, messageType, kind, displayText }) {
      return {
        id: pendingId(clientMessageId),
        clientMessageId,
        conversationId,
        senderDeviceId: state.me.deviceId,
        messageType,
        serverReceivedAt: null,
        kind,
        displayText,
        replyTo: null,
        media: null,
        _status: 'pending',
        _localAt: new Date().toISOString(),
      };
    },
  };
}
