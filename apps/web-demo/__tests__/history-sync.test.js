// What the relay's lists are allowed to change. A conversation's history and
// its preview hold only that conversation's messages: a frame opens under
// the conversation id it carries, so one served in another conversation's
// history would show there under that conversation's peer. And a direct
// conversation bound to its peer keeps that peer whatever the list says.

import { describe, expect, it } from 'vitest';

import { createHistorySync } from '../src/app/services/history-sync.js';
import { createMessages } from '../src/app/services/messages.js';
import { createStore } from '../src/app/store.js';
import { createPinStore } from '../src/crypto/pins.js';
import { textContent } from '../src/domain/content.js';
import { directPeer } from '../src/domain/conversations.js';
import { createHistoryMarks } from '../src/domain/history.js';
import { isShown } from '../src/domain/ingest.js';
import { groupMessages } from '../src/domain/message-groups.js';
import { createPeerResolver, HoldReason } from '../src/domain/peer-bindings.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, createEndpoint, directoryEntryOf, serverMessage } from './support/messaging.js';

const WITH_CAROL = '0d4c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5c';
const OTHER = '1e5d2b3c-4e5f-4a61-9bac-1d2e3f4a5b6d';
const WITH_MALLORY = '2f6e3c4d-5f60-4b72-8cbd-2e3f4a5b6c7e';
const ALICE = { userId: 'u-alice', handle: 'alice' };
const BOB = { userId: 'u-bob', handle: 'bob' };
const CAROL = { userId: 'u-carol', handle: 'carol' };
const MALLORY = { userId: 'u-mallory', handle: 'mallory' };

async function sendText(from, text, conversationId = CONVERSATION) {
  const clientMessageId = `web-${text}`;
  const envelope = await from.secure.seal(conversationId, textContent(text), { clientMessageId });
  const message = serverMessage(envelope, { clientMessageId });
  await from.secure.acknowledge(message);
  return message;
}

// Alice's history sync, with Bob and Carol as contacts, against a relay
// whose answers the test sets: relay.list for GET /conversations, and
// relay.histories for each conversation's messages. stack.peerOf and
// stack.shownPeer resolve as the app's do (src/app/messaging-stack.js).
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
  const { peerOf, shownPeer } = createPeerResolver({
    bindings: { get: (conversationId) => alice.bindings.get(conversationId) },
    conversationOf: (conversationId) => store.conversation(conversationId),
    selfUserId: () => store.state.me?.userId,
  });
  Object.assign(stack, { peerOf, shownPeer });
  const messages = createMessages({ store, stack });
  const sync = createHistorySync({ store, stack, messages, outbox: { drain() {} }, isRealtimeConnected: () => true, toast: () => {} });
  return { alice, bob, carol, directory, relay, store, stack, sync };
}

const direct = (id, peer, extra = {}) => ({ id, type: 'direct', createdAt: '2026-11-11T08:00:00.000Z', members: [ALICE, peer], lastMessage: null, ...extra });
const texts = (store, convId) => store.messagesOf(convId).map((message) => message.displayText);

// The conversation's messages as its panel labels them
// (src/ui/views/chat-view.js, message-list.js): [handle, [texts]] per run,
// every message this device did not send under the shown peer's handle.
function labelled(store, stack, convId) {
  const shown = store.messagesOf(convId).filter((message) => isShown(message));
  const peerHandle = stack.shownPeer(store.conversation(convId))?.handle;
  return groupMessages(shown, { me: store.state.me, peerHandle, dayKey: () => 'day', dayLabel: () => 'day' })
    .flatMap((day) => day.groups.map((group) => [group.senderHandle, group.msgs.map((message) => message.displayText)]));
}

// Alice's crypto resolves the peer of a conversation the harness names none
// for from the list, as the app's does (directPeer, by userId).
function resolveFromList(alice, store) {
  const named = alice.peers;
  alice.peers = {
    get: (conversationId) => named.get(conversationId) ?? directPeer(store.conversation(conversationId), ALICE.userId),
    set: (conversationId, peer) => named.set(conversationId, peer),
  };
}

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
    const { alice, bob, relay, store, stack, sync } = await aliceSync();
    await sendText(alice, 'hello bob');
    const fromBob = await sendText(bob, 'hi alice');
    expect(alice.bindings.get(CONVERSATION)).toEqual(BOB);

    const listings = [
      direct(CONVERSATION, CAROL),
      { ...direct(CONVERSATION, BOB), type: 'group', members: [ALICE, BOB, CAROL] },
      direct(CONVERSATION, { userId: 'u-bob', handle: 'carol' }),
      direct(CONVERSATION, { userId: 'u-carol', handle: 'bob' }),
      // Our own entry renamed: under Carol's handle, first or last.
      { ...direct(CONVERSATION, BOB), members: [{ userId: 'u-alice', handle: 'carol' }, BOB] },
      { ...direct(CONVERSATION, BOB), members: [BOB, { userId: 'u-alice', handle: 'carol' }] },
      { ...direct(CONVERSATION, BOB), members: [{ userId: 'u-alice', handle: 'bob' }, { userId: 'u-bob', handle: 'carol' }] },
    ];
    for (const listing of listings) {
      relay.list = [{ ...listing, disappearingTimerSeconds: 300, lastMessage: fromBob }, direct(OTHER, CAROL)];
      await sync.loadConversations();
      const shown = store.conversation(CONVERSATION);
      expect(shown).toMatchObject({ type: 'direct', members: [ALICE, BOB], disappearingTimerSeconds: 300 });
      expect(directPeer(shown, ALICE.userId)).toEqual(BOB);
      expect(stack.peerOf(CONVERSATION)).toEqual(BOB);
      expect(stack.shownPeer(shown)).toEqual(BOB);
      expect(shown.lastMessage.displayText).toBe('hi alice');
      // A conversation that is bound to nobody follows the list.
      expect(store.conversation(OTHER).members).toEqual([ALICE, CAROL]);
    }
  });

  // A relay that lists our own entry under a contact's handle must not get
  // the conversation, or the messages in it, shown under that contact: what
  // the user sees is what the crypto is about.
  it("keeps showing its peer, and labelling the peer's messages with the peer's handle, when the list renames our own entry", async () => {
    const { alice, bob, relay, store, stack, sync } = await aliceSync();
    const fromAlice = await sendText(alice, 'hello bob');
    const fromBob = await sendText(bob, 'bob says the code is 4471');
    relay.list = [direct(CONVERSATION, BOB), direct(WITH_CAROL, CAROL)];
    relay.histories.set(CONVERSATION, [fromAlice, fromBob]);
    await sync.loadConversations();
    await sync.refreshMessages(CONVERSATION);
    expect(alice.bindings.get(CONVERSATION)).toEqual(BOB);
    expect(labelled(store, stack, CONVERSATION)).toEqual([['alice', ['hello bob']], ['bob', ['bob says the code is 4471']]]);

    // The list now names our own entry in it as Carol.
    relay.list = [
      { ...direct(CONVERSATION, BOB), members: [{ userId: 'u-alice', handle: 'carol' }, BOB], lastMessage: fromBob },
      direct(WITH_CAROL, CAROL),
    ];
    await sync.loadConversations();
    await sync.refreshMessages(CONVERSATION);
    const shown = store.conversation(CONVERSATION);
    expect(shown.members).toEqual([ALICE, BOB]);
    expect(stack.shownPeer(shown)).toEqual(BOB);
    expect(stack.shownPeer(shown)).toEqual(stack.peerOf(CONVERSATION));
    expect(labelled(store, stack, CONVERSATION)).toEqual([['alice', ['hello bob']], ['bob', ['bob says the code is 4471']]]);
    // Only Carol's own conversation is shown under her name.
    expect(store.state.conversations.filter((conv) => stack.shownPeer(conv)?.handle === 'carol').map((conv) => conv.id))
      .toEqual([WITH_CAROL]);
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

// A new conversation is not bound yet: its listing names its peer. The
// relay puts our own entry in it first, under the handle of a contact this
// device is bound to, and lists the new account under its own handle, under
// the contact's, or under ours. The conversation is never shown under the
// contact's handle for anyone but the contact: it shows the new account's
// own handle, or is held when that account is listed under the contact's or
// under ours.
describe('a new conversation whose list puts our own entry under a known handle', () => {
  for (const listedAs of ['mallory', 'bob', 'alice']) {
    it(`is shown under its peer's handle as listed, and held when that is a known one (Mallory listed as @${listedAs})`, async () => {
      const { alice, directory, relay, store, stack, sync } = await aliceSync();
      await sendText(alice, 'hello bob');
      expect(alice.bindings.get(CONVERSATION)).toEqual(BOB);
      const mallory = await createEndpoint({ userId: 'u-mallory', deviceId: 'd-mallory', handle: 'mallory', directory });
      directory.set('mallory', directoryEntryOf(mallory));
      mallory.peers.set(WITH_MALLORY, ALICE);
      resolveFromList(alice, store);
      const fromMallory = await sendText(mallory, 'bob here, new phone, send the code', WITH_MALLORY);

      const listedMallory = { userId: 'u-mallory', handle: listedAs };
      relay.list = [
        direct(CONVERSATION, BOB),
        { ...direct(WITH_MALLORY, MALLORY), members: [{ userId: 'u-alice', handle: 'bob' }, listedMallory], lastMessage: fromMallory },
      ];
      relay.histories.set(WITH_MALLORY, [fromMallory]);
      await sync.loadConversations();
      await sync.refreshMessages(WITH_MALLORY);

      const shown = store.conversation(WITH_MALLORY);
      expect(shown.members).toEqual([ALICE, listedMallory]);
      expect(stack.shownPeer(shown)).toEqual(listedMallory);
      expect(stack.shownPeer(shown)).toEqual(stack.peerOf(WITH_MALLORY));
      const shownAsBob = store.state.conversations.filter((conv) => stack.shownPeer(conv)?.handle === 'bob').map((conv) => conv.id);
      const pins = (await createPinStore(alice.pinKv).pinsFor('u-mallory')).map((pin) => pin.deviceId);
      if (listedAs === 'mallory') {
        // A first contact like any other, under the handle it is listed with.
        expect(alice.bindings.hold(WITH_MALLORY, stack.peerOf(WITH_MALLORY))).toBeNull();
        expect(shownAsBob).toEqual([CONVERSATION]);
        expect(labelled(store, stack, WITH_MALLORY)).toEqual([['mallory', ['bob here, new phone, send the code']]]);
        expect(alice.bindings.get(WITH_MALLORY)).toEqual(MALLORY);
        expect(pins).toEqual(['d-mallory']);
      } else if (listedAs === 'bob') {
        // Shown under Bob's handle, so held: nothing opened, pinned or bound.
        expect(alice.bindings.hold(WITH_MALLORY, stack.peerOf(WITH_MALLORY))).toEqual({ reason: HoldReason.OTHER_ACCOUNT, binding: BOB });
        expect(new Set(shownAsBob)).toEqual(new Set([CONVERSATION, WITH_MALLORY]));
        expect(texts(store, WITH_MALLORY)).not.toContain('bob here, new phone, send the code');
        expect(store.messagesOf(WITH_MALLORY).map((message) => message.kind)).toEqual(['locked']);
        expect(alice.bindings.get(WITH_MALLORY)).toBeNull();
        expect(pins).toEqual([]);
      } else {
        // Shown under Alice's own handle, so held just the same.
        expect(alice.bindings.hold(WITH_MALLORY, stack.peerOf(WITH_MALLORY))).toEqual({ reason: HoldReason.OWN_HANDLE });
        expect(shownAsBob).toEqual([CONVERSATION]);
        expect(texts(store, WITH_MALLORY)).not.toContain('bob here, new phone, send the code');
        expect(store.messagesOf(WITH_MALLORY).map((message) => message.kind)).toEqual(['locked']);
        expect(alice.bindings.get(WITH_MALLORY)).toBeNull();
        expect(pins).toEqual([]);
      }
    });
  }
});
