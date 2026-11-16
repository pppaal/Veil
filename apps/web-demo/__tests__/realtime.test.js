// The push channel's events as the app sees them: what ends a peer's
// "typing…", and what stands in when the channel drops.

import { describe, expect, it, vi } from 'vitest';

import { createRealtime } from '../src/app/services/realtime.js';
import { createStore } from '../src/app/store.js';

const ME = { userId: 'u-me', deviceId: 'd-me', handle: 'alice' };

// A Socket.IO client that only records what the app listens to, so a test
// can play the server's events.
function fakeSocket() {
  const handlers = new Map();
  return {
    connected: true,
    on: (event, handler) => handlers.set(event, handler),
    emit: () => {},
    removeAllListeners: () => handlers.clear(),
    disconnect: () => {},
    fire: (event, ...args) => handlers.get(event)?.(...args),
  };
}

function connected() {
  const store = createStore();
  store.state.me = ME;
  const socket = fakeSocket();
  const history = { startPolling: vi.fn(), slowToHeartbeat: vi.fn(), refreshMessages: vi.fn(), loadConversations: vi.fn() };
  const realtime = createRealtime({
    store,
    stack: { sessionStore: { getAccessToken: () => 'token' } },
    history,
    outbox: { drain: vi.fn() },
    // The view the decrypted message comes to: its kind is the payload's.
    inbound: { onMessageNew: async (message) => ({ id: message.id, kind: message.kind }) },
    messages: { persistConversation: vi.fn() },
    getIo: () => () => socket,
    onStatus: vi.fn(),
    onPeerMessage: vi.fn(),
  });
  realtime.connect();
  socket.fire('connect');
  return { store, socket, history };
}

describe('a peer typing', () => {
  async function typingAfter(kind) {
    const { store, socket } = connected();
    socket.fire('typing.start', { conversationId: 'c1', userId: 'u-bob', handle: 'bob' });
    expect(store.state.typing.has('c1')).toBe(true);
    await socket.fire('message.new', { id: 'm1', conversationId: 'c1', senderDeviceId: 'd-bob', kind });
    return store.state.typing.has('c1');
  }

  it('ends with their message', async () => {
    expect(await typingAfter('text')).toBe(false);
  });

  // As on the phone (realtime_event_router.dart _endsNoTyping): neither is
  // what they were typing.
  it('goes on through a reaction or a system line', async () => {
    expect(await typingAfter('reaction')).toBe(true);
    expect(await typingAfter('system')).toBe(true);
  });
});

describe('a dropped channel', () => {
  it('slows polling to the heartbeat while connected, and brings it back when the channel drops', () => {
    for (const reason of ['io server disconnect', 'transport close']) {
      const { socket, history } = connected();
      expect(history.slowToHeartbeat).toHaveBeenCalledTimes(1);
      expect(history.startPolling).not.toHaveBeenCalled();
      socket.fire('disconnect', reason);
      expect(history.startPolling, reason).toHaveBeenCalledTimes(1);
    }
  });
});
