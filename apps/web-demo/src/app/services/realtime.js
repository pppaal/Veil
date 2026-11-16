// The push channel: the Socket.IO connection to /v1/realtime, the events it
// brings, and the typing indicators this device sends. The channel replays
// nothing, so every (re)connect drains the outbound queue and fetches what
// arrived meanwhile; while it is down, polling (history-sync.js) stands in.

const TYPING_SHOWN_MS = 6000;
const TYPING_SWEEP_MS = 6500;
const TYPING_RESEND_MS = 3000;
const TYPING_IDLE_MS = 4000;

// getIo() -> the socket.io client factory (window.io from socket.io.min.js),
// or nothing when it did not load: then the app stays in polling mode.
// inbound: src/app/services/inbound.js. onStatus(kind) reports the
// connection ('connected', 'connecting' or 'offline'); onPeerMessage() fires
// for every message pushed from another device.
export function createRealtime({ store, stack, history, outbox, inbound, messages, getIo, onStatus, onPeerMessage }) {
  const { state } = store;
  let socket = null;
  const typingSent = new Map(); // convId -> { lastStartAt, stopTimer }

  function clearStaleTyping(convId) {
    const perConv = state.typing.get(convId);
    if (!perConv) return;
    const now = Date.now();
    let changed = false;
    for (const [userId, entry] of perConv) {
      if (entry.expiresAt < now) {
        perConv.delete(userId);
        changed = true;
      }
    }
    if (perConv.size === 0) state.typing.delete(convId);
    if (changed) store.notify('panels');
  }

  // A message from the other side ends its "typing…" there and then, even
  // when no stop arrives: the server drops a stop that follows its start
  // too closely, and a phone may not send one at all. A reaction is not
  // what was being typed, so it ends nothing. A message summary names only
  // the sending device, never its user, so the whole conversation's entry
  // goes; only a direct chat shows typing at all.
  function endTyping(convId, view) {
    if (view?.kind === 'reaction') return;
    if (state.typing.delete(convId)) store.notify('panels');
  }

  function close() {
    if (!socket) return;
    try {
      socket.removeAllListeners();
      socket.disconnect();
    } catch {}
  }

  function listen(s) {
    s.on('connect', () => {
      onStatus('connected');
      history.slowToHeartbeat();
      outbox.drain();
      for (const convId of state.openTabs) history.refreshMessages(convId);
    });
    // The bar's two words for a missing live connection (spec 12.2).
    s.on('disconnect', (reason) => onStatus(reason === 'io server disconnect' ? 'offline' : 'connecting'));
    s.on('connect_error', () => onStatus('offline'));

    // The typing line goes once the message is in the list, before the
    // browser paints again: the message never shows under "typing…".
    s.on('message.new', async (message) => {
      const fromPeer = Boolean(message) && message.senderDeviceId !== state.me?.deviceId;
      if (fromPeer) onPeerMessage();
      let view = null;
      try {
        view = await inbound.onMessageNew(message);
      } finally {
        if (fromPeer) endTyping(message.conversationId, view);
      }
    });
    s.on('message.delivered', ({ messageId, deliveredAt }) => inbound.patchMessage(messageId, { deliveredAt }));
    s.on('message.read', ({ messageId, readAt }) => inbound.patchMessage(messageId, { readAt }));
    s.on('message.edited', (message) => inbound.onMessageEdited(message));
    s.on('message.deleted', ({ messageId, deletedAt }) => inbound.markDeleted(messageId, deletedAt));
    // presence.update goes only to the user's own sockets (the gateway
    // never tells a peer), so it is not listened to: nothing here shows
    // whether someone is online.
    s.on('typing.start', ({ conversationId, userId, handle }) => {
      let perConv = state.typing.get(conversationId);
      if (!perConv) {
        perConv = new Map();
        state.typing.set(conversationId, perConv);
      }
      perConv.set(userId, { handle, expiresAt: Date.now() + TYPING_SHOWN_MS });
      store.notify('panels');
      setTimeout(() => clearStaleTyping(conversationId), TYPING_SWEEP_MS);
    });
    s.on('typing.stop', ({ conversationId, userId }) => {
      const perConv = state.typing.get(conversationId);
      if (!perConv) return;
      perConv.delete(userId);
      if (perConv.size === 0) state.typing.delete(conversationId);
      store.notify('panels');
    });
    s.on('conversation.sync', () => history.loadConversations());
    // The disappearing timer the next sends seal in (contract C4).
    s.on('conversation.timer.changed', ({ conversationId, disappearingTimerSeconds } = {}) => {
      const conv = store.conversation(conversationId);
      if (!conv) return;
      conv.disappearingTimerSeconds = Number.isInteger(disappearingTimerSeconds) ? disappearingTimerSeconds : null;
      messages.persistConversation(conv);
    });
  }

  function stopTyping(convId) {
    const entry = typingSent.get(convId);
    // Nothing to stop unless a start went out. A stop sent anyway (the
    // composer blurs on every redraw) would prime the server's per-socket
    // throttle and swallow the next real start.
    if (!entry) return;
    if (entry.stopTimer) clearTimeout(entry.stopTimer);
    typingSent.delete(convId);
    if (socket?.connected) socket.emit('typing.stop', { conversationId: convId });
  }

  function connect() {
    if (!state.me) return;
    const io = getIo();
    if (typeof io !== 'function') {
      onStatus('offline');
      return;
    }
    close();
    onStatus('connecting');
    socket = io({
      path: '/v1/realtime',
      auth: (send) => send({ token: stack.sessionStore.getAccessToken() }),
      transports: ['websocket', 'polling'],
      reconnection: true,
      reconnectionDelay: 1000,
      reconnectionDelayMax: 30000,
      randomizationFactor: 0.4,
    });
    listen(socket);
  }

  return {
    connect,

    disconnect() {
      close();
      socket = null;
      state.typing.clear();
    },

    isConnected: () => Boolean(socket?.connected),

    // Fresh tokens also revive a socket the server turned away with an
    // expired one; the socket reads the current token on every connect.
    reviveIfDisconnected() {
      if (socket && !socket.connected) socket.connect();
    },

    // The browser says the network is back: connect now rather than when
    // the reconnection backoff (up to 30 seconds) next tries, or never, for
    // a socket the server closed. Only a channel that was open is revived.
    reconnectNow() {
      if (socket && !socket.connected) connect();
    },

    // Typing: one start at most every 3s while the composer has text, and a
    // stop once it has been idle for 4s.
    startTyping(convId) {
      if (!socket?.connected) return;
      const entry = typingSent.get(convId) ?? { lastStartAt: 0, stopTimer: null };
      const now = Date.now();
      if (now - entry.lastStartAt > TYPING_RESEND_MS) {
        socket.emit('typing.start', { conversationId: convId });
        entry.lastStartAt = now;
      }
      if (entry.stopTimer) clearTimeout(entry.stopTimer);
      entry.stopTimer = setTimeout(() => stopTyping(convId), TYPING_IDLE_MS);
      typingSent.set(convId, entry);
    },

    stopTyping,
  };
}
