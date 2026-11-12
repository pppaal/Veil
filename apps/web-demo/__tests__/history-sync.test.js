// What the relay's lists are allowed to change. A conversation's history and
// its preview hold only that conversation's messages: a frame opens under
// the conversation id it carries, so one served in another conversation's
// history would show there under that conversation's peer. And a direct
// conversation bound to its peer keeps that peer whatever the list says.

import { describe, expect, it } from 'vitest';

import { createHistorySync } from '../src/app/services/history-sync.js';
import { createMessages } from '../src/app/services/messages.js';
import { createStore } from '../src/app/store.js';
import { textContent } from '../src/domain/content.js';
import { directPeer, shownPeer } from '../src/domain/conversations.js';
import { createHistoryMarks } from '../src/domain/history.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, createEndpoint, directoryEntryOf, serverMessage } from './support/messaging.js';

const WITH_CAROL = '0d4c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5c';
const OTHER = '1e5d2b3c-4e5f-4a61-9bac-1d2e3f4a5b6d';
const ALICE = { userId: 'u-alice', handle: 'alice' };
const BOB = { userId: 'u-bob', handle: 'bob' };
const CAROL = { userId: 'u-carol', handle: 'carol' };

async function sendText(from, text, conversationId = CONVERSATION) {
  const clientMessageId = `web-${text}`;
  const envelope = await from.secure.seal(conversationId, textContent(text), { clientMessageId });
  const message = serverMessage(envelope, { clientMessageId });
  await from.secure.acknowledge(message);
  return message;
}

// Alice's history sync, with Bob and Carol as contacts, against a relay
// whose answers the test sets: relay.list for GET /conversations, and
// relay.histories for each conversation's messages.
async function aliceSync() {
  const { alice, bob, directory } = await conversation();
  const carol = await createEndpoint({ userId: 'u-carol', deviceId: 'd-carol', handle: 'carol', directory });
  directory.set('carol', directoryEntryOf(carol));
  alice.peers.set(WITH_CAROL, CAROL);
  carol.peers.set(WITH_CAROL, ALICE);

  const relay = { list: [], histories: new Map() };
  const store = createStore();
  store.state.me = { ...ALICE, deviceId: 'd-alice' };
  const stack = {
    secure: alice.secure,
    media: null,
    historyMarks: createHistoryMarks(createMemoryKv('conversationId')),
    identityDb: { put: async () => {}, delete: async () => {} },
    // The harness rebuilds the bindings on every restart.
    get bindings() {
      return alice.bindings;
    },
    bindSessions: (conversations) => alice.bindings.bindSessions(conversations, {
      selfUserId: ALICE.userId,
      hasSession: (id) => alice.device.cipher.hasSession(id),
    }),
    authedApi: async (path) => {
      if (path === '/conversations') return structuredClone(relay.list);
      const [, id] = path.match(/^\/conversations\/([^/]+)\/messages/);
      return { items: structuredClone(relay.histories.get(id) ?? []), nextCursor: null };
    },
  };
  const messages = createMessages({ store, stack });
  const sync = createHistorySync({ store, stack, messages, outbox: { drain() {} }, isRealtimeConnected: () => true, toast: () => {} });
  return { alice, bob, carol, relay, store, stack, sync };
}

const direct = (id, peer, extra = {}) => ({ id, type: 'direct', createdAt: '2026-11-11T08:00:00.000Z', members: [ALICE, peer], lastMessage: null, ...extra });
const texts = (store, convId) => store.messagesOf(convId).map((message) => message.displayText);

describe('a conversation shows only its own messages', () => {
  it('drops a frame from another conversation served in its history, and keeps its mark short of it', async () => {
    const { bob, carol, relay, store, stack, sync } = await aliceSync();
    const fromBob = await sendText(bob, 'hello from bob');
    const fromCarol = await sendText(carol, 'carol: meet me at 9', WITH_CAROL);
    relay.list = [direct(CONVERSATION, BOB), direct(WITH_CAROL, CAROL)];
    relay.histories.set(CONVERSATION, [fromBob, fromCarol]);
    await sync.loadConversations();

    await sync.refreshMessages(CONVERSATION);
    expect(texts(store, CONVERSATION)).toEqual(['hello from bob']);
    expect(store.messagesOf(CONVERSATION).every((message) => message.conversationId === CONVERSATION)).toBe(true);
    expect(stack.historyMarks.through(CONVERSATION)).toBe(fromBob.conversationOrder);

    // In its own conversation it opens as it should.
    relay.histories.set(WITH_CAROL, [fromCarol]);
    await sync.refreshMessages(WITH_CAROL);
    expect(texts(store, WITH_CAROL)).toEqual(['carol: meet me at 9']);
  });

  it('takes no last message from another conversation as its preview', async () => {
    const { carol, relay, store, sync } = await aliceSync();
    const fromCarol = await sendText(carol, 'carol: only for alice', WITH_CAROL);
    relay.list = [direct(CONVERSATION, BOB, { lastMessage: fromCarol }), direct(WITH_CAROL, CAROL, { lastMessage: fromCarol })];
    await sync.loadConversations();
    expect(store.conversation(CONVERSATION).lastMessage).toBeNull();
    expect(store.conversation(WITH_CAROL).lastMessage.displayText).toBe('carol: only for alice');
  });
});

describe('a direct conversation bound to its peer', () => {
  it('keeps that peer whatever the list says, and takes its last message and timer', async () => {
    const { alice, bob, relay, store, sync } = await aliceSync();
    await sendText(alice, 'hello bob');
    const fromBob = await sendText(bob, 'hi alice');
    expect(alice.bindings.get(CONVERSATION)).toEqual(BOB);

    const listings = [
      direct(CONVERSATION, CAROL),
      { ...direct(CONVERSATION, BOB), type: 'group', members: [ALICE, BOB, CAROL] },
      direct(CONVERSATION, { userId: 'u-bob', handle: 'carol' }),
      direct(CONVERSATION, { userId: 'u-carol', handle: 'bob' }),
    ];
    for (const listing of listings) {
      relay.list = [{ ...listing, disappearingTimerSeconds: 300, lastMessage: fromBob }, direct(OTHER, CAROL)];
      await sync.loadConversations();
      const shown = store.conversation(CONVERSATION);
      expect(shown).toMatchObject({ type: 'direct', members: [ALICE, BOB], disappearingTimerSeconds: 300 });
      expect(directPeer(shown, ALICE.userId)).toEqual(BOB);
      expect(shownPeer(shown, ALICE.handle)).toEqual(BOB);
      expect(shown.lastMessage.displayText).toBe('hi alice');
      // A conversation that is bound to nobody follows the list.
      expect(store.conversation(OTHER).members).toEqual([ALICE, CAROL]);
    }
  });

  it('binds a session from before bindings existed before a list can name someone else', async () => {
    const { alice, relay, store, sync } = await aliceSync();
    await sendText(alice, 'hello bob');
    alice.bindingKv.rows.clear();
    await alice.restart();
    expect(alice.bindings.get(CONVERSATION)).toBeNull();

    // The list as the earlier build last showed it, then a relabelled one.
    relay.list = [direct(CONVERSATION, BOB)];
    await sync.loadConversations();
    relay.list = [direct(CONVERSATION, CAROL)];
    await sync.loadConversations();
    expect(alice.bindings.get(CONVERSATION)).toEqual(BOB);
    expect(store.conversation(CONVERSATION).members).toEqual([ALICE, BOB]);
  });
});
