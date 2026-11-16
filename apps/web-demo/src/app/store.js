// The app's one state container: who is signed in, the conversations and
// the messages loaded for each, and what the screen shows. Services change
// it and then notify a topic; the views that subscribed to the topic draw
// again. Notification is synchronous, so a view is redrawn exactly where the
// change happened.
//
// Topics: 'sidebar', 'panels', 'tabs', and 'session-reset' when the signed-in
// session's state is dropped (sign-out, rejection, wipe, transfer).

import { isMutedAt } from '../domain/mute.js';

// mutedConversations: convId -> when the mute ends (ms) or null, or ids
// alone for mutes with no end (src/domain/mute.js).
const muteMap = (muted) => (muted instanceof Map ? new Map(muted) : new Map([...muted].map((id) => [id, null])));

export function createStore({ mutedConversations = [], soundsEnabled = false } = {}) {
  const state = {
    me: null, // session record: handle, userId, deviceId, identity keys (src/crypto/identity.js), tokens
    conversations: [], // ConversationSummary[], lastMessage ingested
    conversationsLoaded: false, // false until the first /conversations response lands
    messagesByConv: new Map(), // convId -> message views (src/domain/ingest.js) + receipts
    openTabs: [], // convId[] in the order they were opened
    activeConv: null, // primary panel convId (or an opened Kakao archive's id)
    secondaryConv: null, // split view's right panel convId
    splitView: false,
    typing: new Map(), // convId -> Map<userId, { handle, expiresAt }>
    replyDrafts: new Map(), // convId -> { id, snippet, sender } awaiting send
    editing: new Map(), // convId -> { id, snippet } of our message being edited in the composer
    // Unsent text is plaintext: it lives in memory only, never on disk.
    drafts: new Map(), // convId -> text
    focusClaims: new Set(), // convIds whose composer takes focus on the next draw
    searches: new Map(), // convId -> { open, query, idx }
    scrollTops: new Map(), // convId -> last scrollTop of its message list
    muted: muteMap(mutedConversations), // convId -> end of the mute (ms) or null
    blocked: null, // userIds this account blocked, as the server last listed them; null until it has
    archives: [], // Kakao archive sidebar rows (src/platform/persist.js kakaoArchiveMeta)
    soundsEnabled,
  };
  const listeners = new Map();

  const messagesOf = (convId) => state.messagesByConv.get(convId) || [];

  return {
    state,

    subscribe(topic, listener) {
      if (!listeners.has(topic)) listeners.set(topic, new Set());
      listeners.get(topic).add(listener);
    },

    notify(...topics) {
      for (const topic of topics) for (const listener of listeners.get(topic) ?? []) listener();
    },

    conversation: (convId) => state.conversations.find((conv) => conv.id === convId),
    messagesOf,
    isOnScreen: (convId) => convId === state.activeConv || convId === state.secondaryConv,
    // Whether the conversation's notifications are off right now.
    isMuted: (convId) => isMutedAt(state.muted, convId, Date.now()),
    // Whether this account blocked the user, as far as this browser knows.
    isBlocked: (userId) => Boolean(userId && state.blocked?.has(userId)),

    // A message of a conversation, from its loaded list or as its last message.
    findMessage(convId, messageId) {
      const loaded = messagesOf(convId).find((message) => message.id === messageId);
      if (loaded) return loaded;
      const last = state.conversations.find((conv) => conv.id === convId)?.lastMessage;
      return last?.id === messageId ? last : null;
    },

    // Where a loaded message sits: { convId, list, index, message }, or null.
    locateMessage(messageId) {
      for (const [convId, list] of state.messagesByConv) {
        const index = list.findIndex((message) => message.id === messageId);
        if (index >= 0) return { convId, list, index, message: list[index] };
      }
      return null;
    },

    // Puts an own message in place of the one with its client id, or last.
    putOwnMessage(convId, clientMessageId, view) {
      const list = messagesOf(convId);
      const index = list.findIndex((message) => message.clientMessageId === clientMessageId);
      if (index >= 0) list[index] = view;
      else list.push(view);
      state.messagesByConv.set(convId, list);
    },

    // Drops everything the signed-in session put here; preferences stay.
    resetSession() {
      state.me = null;
      state.conversations = [];
      state.conversationsLoaded = false;
      state.messagesByConv.clear();
      state.activeConv = null;
      state.secondaryConv = null;
      state.openTabs = [];
      state.splitView = false;
      state.replyDrafts.clear();
      state.editing.clear();
      state.drafts.clear();
      state.searches.clear();
      state.scrollTops.clear();
      state.typing.clear();
      state.blocked = null;
    },
  };
}
