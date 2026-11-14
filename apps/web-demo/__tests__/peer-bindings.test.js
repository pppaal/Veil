// Whom each direct conversation is with, once its crypto first admitted an
// identity for it: recorded once, never replaced, read back after a reload,
// and never guessed at while the record cannot be read.

import { describe, expect, it, vi } from 'vitest';

import {
  adoptedConversation,
  createConversationVerifier,
  createPeerBindings,
  createPeerResolver,
  HoldReason,
} from '../src/domain/peer-bindings.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { BOB_LOOKALIKES } from './support/lookalikes.js';

const ALICE = { userId: 'u-alice', handle: 'alice' };
const BOB = { userId: 'u-bob', handle: 'bob' };
const MALLORY = { userId: 'u-mallory', handle: 'mallory' };
const key = new Uint8Array(32).fill(1);

describe('peer bindings', () => {
  it('bind once, are never replaced, and are read back after a reload', async () => {
    const kv = createMemoryKv('conversationId');
    const bindings = createPeerBindings(kv);
    await bindings.load();
    await bindings.bind('c-1', BOB);
    await bindings.bind('c-1', MALLORY);
    expect(bindings.get('c-1')).toEqual(BOB);
    expect(bindings.get('c-2')).toBeNull();

    const reloaded = createPeerBindings(kv);
    expect(reloaded.get('c-1')).toBeNull();
    await reloaded.load();
    expect(reloaded.get('c-1')).toEqual(BOB);
    reloaded.reset();
    expect(reloaded.get('c-1')).toBeNull();
  });

  it('admit and bind nothing while the record cannot be read, and work once it can', async () => {
    const kv = createMemoryKv('conversationId');
    await kv.put({ conversationId: 'c-1', ...BOB });
    const all = kv.all;
    kv.all = vi.fn().mockRejectedValueOnce(new Error('storage unavailable')).mockImplementation(all);
    const bindings = createPeerBindings(kv);
    await expect(bindings.load()).rejects.toThrow('storage unavailable');
    await expect(bindings.bind('c-2', MALLORY)).rejects.toThrow();

    // The listing names Mallory for c-1, which the unread record binds to Bob.
    const trust = { admit: vi.fn(async () => true) };
    const peerOf = (conversationId) => bindings.get(conversationId) ?? MALLORY;
    const verifyIdentity = createConversationVerifier({ bindings, trust, peerOf });
    kv.all = vi.fn().mockRejectedValueOnce(new Error('still unavailable')).mockImplementation(all);
    expect(await verifyIdentity({ conversationId: 'c-1', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(false);
    expect(trust.admit).not.toHaveBeenCalled();
    expect(await kv.get('c-2')).toBeNull();

    // Readable again: c-1 is judged for Bob, as bound.
    expect(await verifyIdentity({ conversationId: 'c-1', remoteDeviceId: 'd-bob', identityKey: key })).toBe(true);
    expect(trust.admit).toHaveBeenCalledWith('u-bob', 'd-bob', key);
    expect(bindings.get('c-1')).toEqual(BOB);
  });

  it('bind a conversation to the peer the pins admitted, and only once they do', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    const admitted = new Set(['d-bob']);
    const trust = { admit: vi.fn(async (userId, deviceId) => admitted.has(deviceId)) };
    const listed = new Map([['c-1', BOB]]);
    const verifyIdentity = createConversationVerifier({ bindings, trust, peerOf: (id) => bindings.get(id) ?? listed.get(id) ?? null });

    expect(await verifyIdentity({ conversationId: 'c-1', remoteDeviceId: 'd-other', identityKey: key })).toBe(false);
    expect(bindings.get('c-1')).toBeNull();
    expect(await verifyIdentity({ conversationId: 'c-1', remoteDeviceId: 'd-bob', identityKey: key })).toBe(true);
    expect(bindings.get('c-1')).toEqual(BOB);

    // The listing names someone else now: the conversation is still Bob's.
    listed.set('c-1', MALLORY);
    expect(await verifyIdentity({ conversationId: 'c-1', remoteDeviceId: 'd-bob', identityKey: key })).toBe(true);
    expect(trust.admit).toHaveBeenLastCalledWith('u-bob', 'd-bob', key);
    // No peer at all (a group, or not signed in): nothing is admitted.
    expect(await verifyIdentity({ conversationId: 'c-9', remoteDeviceId: 'd-bob', identityKey: key })).toBe(false);
  });

  it('hold a handle known under another account, until that conversation is bound', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    await bindings.bind('c-bob', BOB);
    const lookalike = { userId: 'u-mallory', handle: 'Bob' };
    expect(bindings.handleConflict('c-new', lookalike)).toEqual(BOB);
    expect(bindings.handleConflict('c-new', BOB)).toBeNull();
    expect(bindings.handleConflict('c-new', MALLORY)).toBeNull();
    expect(bindings.handleConflict('c-bob', lookalike)).toBeNull();

    const trust = { admit: vi.fn(async () => true) };
    const verifyIdentity = createConversationVerifier({ bindings, trust, peerOf: (id) => bindings.get(id) ?? lookalike });
    expect(await verifyIdentity({ conversationId: 'c-new', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(false);
    expect(trust.admit).not.toHaveBeenCalled();
    await bindings.bind('c-new', lookalike);
    expect(bindings.handleConflict('c-new', lookalike)).toBeNull();
    expect(await verifyIdentity({ conversationId: 'c-new', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(true);
  });

  // A hostile relay lists another account under a lookalike of a handle
  // this device knows: it renders as 'bob' but equals none, so only the
  // handle grammar tells.
  for (const [what, lookalike] of Object.entries({ ...BOB_LOOKALIKES, 'a capital B': 'Bob' })) {
    it(`hold a handle no honest server issues (bob with ${what}), until that conversation is bound`, async () => {
      const bindings = createPeerBindings(createMemoryKv('conversationId'));
      await bindings.load();
      const listed = { userId: 'u-mallory', handle: lookalike };
      // Held on a device that knows no one, too.
      expect(bindings.hold('c-new', listed)).toEqual({ reason: HoldReason.UNISSUED_HANDLE });
      await bindings.bind('c-bob', BOB);
      expect(bindings.hold('c-new', listed)).toEqual({ reason: HoldReason.UNISSUED_HANDLE });

      const trust = { admit: vi.fn(async () => true) };
      const verifyIdentity = createConversationVerifier({ bindings, trust, peerOf: (id) => bindings.get(id) ?? listed });
      expect(await verifyIdentity({ conversationId: 'c-new', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(false);
      expect(trust.admit).not.toHaveBeenCalled();
      expect(bindings.get('c-new')).toBeNull();

      // Acknowledged (bound), it is kept as it is.
      await bindings.bind('c-new', listed);
      expect(bindings.hold('c-new', listed)).toBeNull();
      expect(await verifyIdentity({ conversationId: 'c-new', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(true);
    });
  }

  it('hold an issued handle only when it is known under another account', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    await bindings.bind('c-bob', BOB);
    expect(bindings.hold('c-new', { userId: 'u-mallory', handle: 'bob' })).toEqual({ reason: HoldReason.OTHER_ACCOUNT, binding: BOB });
    expect(bindings.hold('c-new', BOB)).toBeNull();
    expect(bindings.hold('c-new', MALLORY)).toBeNull();
    expect(bindings.hold('c-new', { userId: 'u-veil', handle: 'veil.operator' })).toBeNull();
    // A bound conversation keeps its peer whatever it is listed under.
    expect(bindings.hold('c-bob', { userId: 'u-mallory', handle: 'bob​' })).toBeNull();
    // No peer (a group): nothing to hold.
    expect(bindings.hold('g-1', null)).toBeNull();
  });

  it('bind the listed sessions that predate them, each looked at once', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    const sessions = new Set(['c-1']);
    const hasSession = vi.fn(async (id) => sessions.has(id));
    const direct = (id, peer) => ({ id, type: 'direct', members: [ALICE, peer] });
    const listed = [direct('c-1', BOB), direct('c-2', MALLORY), { id: 'g-1', type: 'group', members: [ALICE, BOB, MALLORY] }];
    await bindings.bindSessions(listed, { selfUserId: 'u-alice', hasSession });
    expect(bindings.get('c-1')).toEqual(BOB);
    expect(bindings.get('c-2')).toBeNull();
    expect(bindings.get('g-1')).toBeNull();
    sessions.add('c-2');
    await bindings.bindSessions(listed, { selfUserId: 'u-alice', hasSession });
    expect(hasSession.mock.calls.map(([id]) => id)).toEqual(['c-1', 'c-2']);
    expect(bindings.get('c-2')).toBeNull();
  });

  // Our own handle names one account, ours: no honest server lists another
  // account under it.
  it('hold another account listed under our own handle', async () => {
    let self = ALICE;
    const bindings = createPeerBindings(createMemoryKv('conversationId'), { self: () => self });
    await bindings.load();
    const posing = { userId: 'u-mallory', handle: 'alice' };
    expect(bindings.hold('c-new', posing)).toEqual({ reason: HoldReason.OWN_HANDLE });
    expect(bindings.hold('c-new', { userId: 'u-mallory', handle: 'ALICE' })).toEqual({ reason: HoldReason.UNISSUED_HANDLE });
    expect(bindings.hold('c-new', MALLORY)).toBeNull();
    expect(bindings.hold('c-new', BOB)).toBeNull();
    // A note to self is ours, not another account's.
    expect(bindings.hold('c-new', ALICE)).toBeNull();
    // The verifier admits nothing for it, and binds nothing.
    const trust = { admit: vi.fn(async () => true) };
    const verifyIdentity = createConversationVerifier({ bindings, trust, peerOf: () => posing });
    expect(await verifyIdentity({ conversationId: 'c-new', remoteDeviceId: 'd-mallory', identityKey: key })).toBe(false);
    expect(trust.admit).not.toHaveBeenCalled();
    expect(bindings.get('c-new')).toBeNull();
    // Signed out, there is no own handle to hold for.
    self = null;
    expect(bindings.hold('c-new', posing)).toBeNull();
    // Once the user chose to talk to the account, it is bound and not held.
    self = ALICE;
    await bindings.bind('c-new', posing);
    expect(bindings.hold('c-new', posing)).toBeNull();
  });

  it('leave a session listed under our own handle unbound, and so held', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'), { self: () => ALICE });
    await bindings.load();
    const posing = { userId: 'u-mallory', handle: 'alice' };
    const listed = [{ id: 'c-1', type: 'direct', members: [ALICE, posing] }, { id: 'c-2', type: 'direct', members: [ALICE, BOB] }];
    await bindings.bindSessions(listed, { selfUserId: 'u-alice', hasSession: async () => true });
    expect(bindings.get('c-1')).toBeNull();
    expect(bindings.hold('c-1', posing)).toEqual({ reason: HoldReason.OWN_HANDLE });
    expect(bindings.get('c-2')).toEqual(BOB);
  });

  it('leave a session listed under a handle no honest server issues unbound, and so held', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    const lookalike = { userId: 'u-mallory', handle: BOB_LOOKALIKES['a zero-width space'] };
    const listed = [{ id: 'c-1', type: 'direct', members: [ALICE, lookalike] }];
    await bindings.bindSessions(listed, { selfUserId: 'u-alice', hasSession: async () => true });
    expect(bindings.get('c-1')).toBeNull();
    expect(bindings.hold('c-1', lookalike)).toEqual({ reason: HoldReason.UNISSUED_HANDLE });
  });
});

describe('adoptedConversation', () => {
  const me = { userId: 'u-alice', handle: 'alice', deviceId: 'd-alice' };
  const listing = (type, members) => ({ id: 'c-1', type, members, disappearingTimerSeconds: 60, lastMessage: { id: 'm-9' } });

  it('keeps the bound peer whatever the listing names, and takes the rest from it', () => {
    const relabelled = adoptedConversation(listing('direct', [ALICE, MALLORY]), BOB, me);
    expect(relabelled).toMatchObject({ type: 'direct', members: [ALICE, BOB], disappearingTimerSeconds: 60, lastMessage: { id: 'm-9' } });
    expect(adoptedConversation(listing('group', [ALICE, MALLORY, BOB]), BOB, me)).toMatchObject({ type: 'direct', members: [ALICE, BOB] });
    expect(adoptedConversation(listing('direct', [ALICE, { userId: 'u-bob', handle: 'mallory' }]), BOB, me).members)
      .toEqual([ALICE, BOB]);
    expect(adoptedConversation(listing('direct', [MALLORY]), BOB, me).members).toEqual([ALICE, BOB]);
  });

  it("takes our own entry from this device, never from the listing, bound or not", () => {
    const renamedSelf = { userId: 'u-alice', handle: 'bob' };
    expect(adoptedConversation(listing('direct', [renamedSelf, BOB]), BOB, me).members).toEqual([ALICE, BOB]);
    expect(adoptedConversation(listing('direct', [BOB, renamedSelf]), BOB, me).members).toEqual([ALICE, BOB]);
    expect(adoptedConversation(listing('direct', [renamedSelf, MALLORY]), null, me).members).toEqual([ALICE, MALLORY]);
    expect(adoptedConversation(listing('group', [MALLORY, renamedSelf, BOB]), null, me).members).toEqual([MALLORY, ALICE, BOB]);
  });

  it('leaves the rest of an unbound conversation as listed', () => {
    const listed = listing('direct', [ALICE, MALLORY]);
    expect(adoptedConversation(listed, null, me)).toEqual(listed);
    expect(adoptedConversation(listed, null, null)).toBe(listed);
  });
});

describe('createPeerResolver', () => {
  const me = { userId: 'u-alice', handle: 'alice' };

  it('shows a direct conversation under the peer its crypto is about, whatever handle our own entry is listed under', async () => {
    const bindings = createPeerBindings(createMemoryKv('conversationId'));
    await bindings.load();
    await bindings.bind('c-bob', BOB);
    // The relay lists our own entry under Carol's handle in the bound
    // conversation, and under Bob's in Mallory's new one.
    const listed = new Map([
      ['c-bob', { id: 'c-bob', type: 'direct', members: [{ userId: 'u-alice', handle: 'carol' }, BOB] }],
      ['c-new', { id: 'c-new', type: 'direct', members: [{ userId: 'u-alice', handle: 'bob' }, MALLORY] }],
    ]);
    const raw = createPeerResolver({ bindings, conversationOf: (id) => listed.get(id), selfUserId: () => me.userId });
    expect(raw.shownPeer(listed.get('c-bob'))).toEqual(BOB);
    expect(raw.shownPeer(listed.get('c-new'))).toEqual(MALLORY);
    expect(raw.shownPeer(listed.get('c-new'))).toEqual(raw.peerOf('c-new'));
    expect(bindings.hold('c-new', raw.peerOf('c-new'))).toBeNull();

    // As adopted, the same.
    const adopted = new Map([...listed].map(([id, conv]) => [id, adoptedConversation(conv, bindings.get(id), me)]));
    const resolver = createPeerResolver({ bindings, conversationOf: (id) => adopted.get(id), selfUserId: () => me.userId });
    expect(resolver.shownPeer(adopted.get('c-bob'))).toEqual(BOB);
    expect(resolver.shownPeer(adopted.get('c-new'))).toEqual(MALLORY);
  });
});
