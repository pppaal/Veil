// What the push channel delivers about messages: new ones, receipts, edits
// and deletions, each brought into the store through the one ingest path.

import { isShown } from '../../domain/ingest.js';
import { serializeMessageForCache } from '../../platform/persist.js';

// history: src/app/services/history-sync.js; notifications:
// src/app/services/notifications.js.
export function createInbound({ store, messages, history, notifications }) {
  const { state } = store;

  function bumpConversation(convId, message) {
    const conv = store.conversation(convId);
    if (conv) {
      conv.lastMessage = message;
      messages.sortConversations();
    }
    store.notify('sidebar');
    if (store.isOnScreen(convId)) store.notify('panels');
  }

  return {
    async onMessageNew(raw) {
      const convId = raw.conversationId;
      const list = store.messagesOf(convId);
      if (list.some((message) => message.id === raw.id)) return;
      // The first message of a conversation can arrive before the
      // conversation list names its members, and a session-starting frame is
      // only accepted for the identity pinned for the member who sent it.
      if (!store.conversation(convId)) await history.loadConversations();
      // The server's echo of our own send replaces the optimistic entry and
      // reuses its already-decoded content.
      const pendingIndex = raw.clientMessageId ? list.findIndex((message) => message.clientMessageId === raw.clientMessageId) : -1;
      if (pendingIndex >= 0) {
        const view = await messages.ingest(raw, { previous: list[pendingIndex] });
        list[pendingIndex] = view;
        state.messagesByConv.set(convId, list);
        bumpConversation(convId, view);
        return;
      }
      const view = await messages.ingest(raw, { previous: store.findMessage(convId, raw.id) });
      if (list.some((message) => message.id === view.id)) return;
      list.push(view);
      state.messagesByConv.set(convId, list);
      bumpConversation(convId, view);
      // A peer's message, not our own echo, and not a reaction or an expired
      // message, is one to be told about while the tab is hidden.
      if (view.senderDeviceId !== state.me?.deviceId && isShown(view)) {
        notifications.bumpUnread();
        notifications.show(view);
      }
    },

    patchMessage(messageId, patch) {
      const found = store.locateMessage(messageId);
      if (!found) return;
      Object.assign(found.message, patch);
      if (store.isOnScreen(found.convId)) store.notify('panels');
    },

    async markDeleted(messageId, deletedAt) {
      const found = store.locateMessage(messageId);
      if (!found) return;
      messages.revokeBlobUrls(found.message);
      await messages.reingestInPlace(messageId, Object.assign(serializeMessageForCache(found.message), { deletedAt }));
    },

    // Edits go through the same ingest path as new messages, so an edited
    // reply renders its text rather than the raw payload.
    async onMessageEdited(summary) {
      const found = store.locateMessage(summary.id);
      if (!found) return;
      // Only the original sender can edit; the device id is never taken
      // from the edit.
      const edited = Object.assign(serializeMessageForCache(found.message), {
        ciphertext: summary.ciphertext,
        nonce: summary.nonce,
        editedAt: summary.editedAt ?? found.message.editedAt,
      });
      await messages.reingestInPlace(summary.id, edited, { editCount: summary.editCount ?? found.message.editCount });
    },
  };
}
