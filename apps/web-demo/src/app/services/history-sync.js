// Conversations and history from the relay: the cache painted first, the
// conversation list, history paged back per conversation
// (src/domain/history.js), the expiry sweep, and the polling that runs it
// all while the push channel is down or slow.

import { expiryNow, isPast } from '../../core/expiry.js';
import { fetchHistory, mergeHistory } from '../../domain/history.js';
import { adoptedConversation } from '../../domain/peer-bindings.js';
import { AuthError } from '../../platform/api-client.js';
import { serializeMessageForCache } from '../../platform/persist.js';

const POLL_MS = 4000;
const HEARTBEAT_MS = 30_000;

// outbox: src/app/services/outbox.js; isRealtimeConnected() tells whether
// the push channel delivers per-message updates; toast(message, kind).
export function createHistorySync({ store, stack, messages, outbox, isRealtimeConnected, toast }) {
  const { state } = store;
  let pollTimer = null;

  // Installs a fresh conversation list. The envelope crypto resolves peers
  // from the store's conversations, so the list goes in first and last
  // messages are ingested after; meanwhile each keeps its previous view.
  // A direct conversation bound to its peer (src/domain/peer-bindings.js)
  // keeps that peer whatever the list says; sessions from before bindings
  // existed are bound first, to the peer the list being replaced names. Our
  // own entry in every conversation is this device's, never the list's. A
  // last message that names another conversation is no preview of this one:
  // its frame authenticates under the id it carries, and the relay must not
  // file one contact's words under another (see refreshMessages).
  async function adoptConversations(listed) {
    await stack.bindSessions(state.conversations).catch((error) => console.warn('binding sessions failed', error));
    const conversations = listed.map((conv) => adoptedConversation(conv, stack.bindings.get(conv.id), state.me));
    for (const conv of conversations) if (conv.lastMessage?.conversationId !== conv.id) conv.lastMessage = null;
    const incoming = conversations.filter((conv) => conv.lastMessage).map((conv) => {
      const raw = conv.lastMessage;
      conv.lastMessage = store.findMessage(conv.id, raw.id);
      return [conv, raw];
    });
    state.conversations = conversations;
    await Promise.all(incoming.map(async ([conv, raw]) => {
      conv.lastMessage = await messages.ingest(raw, { previous: conv.lastMessage });
    }));
    messages.sortConversations();
  }

  async function loadConversations() {
    try {
      const response = await stack.authedApi('/conversations');
      await adoptConversations(Array.isArray(response) ? response : (response.items ?? []));
      state.conversationsLoaded = true;
      // Search state of conversations that no longer exist goes, so the map
      // stays bounded over long sessions.
      const live = new Set(state.conversations.map((conv) => conv.id));
      for (const convId of Array.from(state.searches.keys())) if (!live.has(convId)) state.searches.delete(convId);
      store.notify('sidebar');
      messages.persistAllConversations();
      outbox.drain();
    } catch (error) {
      if (error instanceof AuthError) return;
      toast(error.message, 'error');
    }
  }

  async function refreshMessages(convId) {
    const target = convId ?? state.activeConv;
    if (!target) return;
    try {
      // Only the conversation's own messages: a frame opens under the
      // conversation id it carries (its AAD binds that id), so one the relay
      // slipped into this history from another conversation would open
      // there and show here, under this conversation's peer. Dropped before
      // anything sees it, the history mark included.
      const items = (await fetchHistory(
        (query) => stack.authedApi(`/conversations/${target}/messages?${query}`),
        { through: stack.historyMarks.through(target) },
      )).filter((raw) => raw?.conversationId === target);
      // One at a time and oldest first, so each ratchet chain moves forward
      // in order. Unchanged messages keep their views (no re-decrypt, blob
      // URLs intact).
      const fresh = [];
      for (const raw of items) fresh.push(await messages.ingest(raw, { previous: store.findMessage(target, raw.id) }));
      messages.setMessages(target, mergeHistory(store.messagesOf(target), items, fresh));
      if (store.isOnScreen(target)) store.notify('panels');
      // Cached before the mark moves past them, so a reload in between finds
      // them in the cache or fetches them again.
      await messages.persistMessages(fresh);
      await stack.historyMarks.advance(target, items.at(-1)?.conversationOrder);
    } catch {
      // A rejected session is handled by the session; anything else retries
      // on the next poll.
    }
  }

  // Contract C4 on this device: once a message's expiry passes it leaves
  // every list and what was kept of it is retired, through the same ingest
  // path as everything else. Stored contents of messages that are not
  // loaded expire with them.
  async function expireDueMessages() {
    const now = expiryNow();
    const due = (message) => isPast(message?.expiresAtMs, now);
    const expire = (message) => messages.ingest(serializeMessageForCache(message), { previous: message });
    let changed = false;
    for (const [convId, list] of state.messagesByConv) {
      const dueMessages = list.filter(due);
      if (dueMessages.length === 0) continue;
      const expired = new Map((await Promise.all(dueMessages.map(expire))).map((view) => [view.id, view]));
      // Swapped into the list as it is now: a message may have arrived meanwhile.
      messages.setMessages(convId, store.messagesOf(convId).map((message) => expired.get(message.id) ?? message));
      for (const view of expired.values()) messages.persistMessage(view);
      changed = true;
    }
    for (const conv of state.conversations) {
      if (!due(conv.lastMessage)) continue;
      const view = await expire(conv.lastMessage);
      if (conv.lastMessage?.id === view.id) conv.lastMessage = view;
      changed = true;
    }
    await stack.secure.retireExpired();
    if (changed) store.notify('sidebar', 'panels');
  }

  const stopPolling = () => {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  };

  return {
    POLL_MS,
    loadConversations,
    refreshMessages,

    // Paints the cached conversations and messages before the network
    // answers.
    async hydrateFromCache() {
      try {
        const cachedConvs = await stack.idb.all('conversations');
        if (cachedConvs.length === 0) return;
        await adoptConversations(cachedConvs);
        const rows = await stack.idb.all('messages');
        const byConv = new Map();
        for (const row of rows) {
          const list = byConv.get(row.conversationId) ?? [];
          list.push(row);
          byConv.set(row.conversationId, list);
        }
        await Promise.all([...byConv].map(async ([convId, list]) => {
          list.sort((a, b) => a.conversationOrder - b.conversationOrder);
          const views = await Promise.all(list.map((row) => messages.ingest(row, { previous: store.findMessage(convId, row.id) })));
          messages.setMessages(convId, views);
          for (const view of views) if (view.kind === 'expired') messages.persistMessage(view);
        }));
      } catch (error) {
        console.warn('hydrate from cache failed', error);
      }
    },

    // A safety net while the push channel is pending or down: the expiry
    // sweep runs on every tick, hidden tab or not.
    startPolling() {
      stopPolling();
      pollTimer = setInterval(async () => {
        if (!state.me) return;
        await expireDueMessages().catch((error) => console.warn('expiry sweep failed', error));
        if (document.hidden) return;
        await loadConversations();
        if (isRealtimeConnected()) return;
        for (const convId of state.openTabs) await refreshMessages(convId);
      }, POLL_MS);
    },

    // With the push channel up, only the conversation list is polled, slowly.
    slowToHeartbeat() {
      stopPolling();
      pollTimer = setInterval(loadConversations, HEARTBEAT_MS);
    },

    stopPolling,
  };
}
