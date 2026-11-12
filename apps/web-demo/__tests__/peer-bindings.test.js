// Whom each direct conversation is with, once its crypto first admitted an
// identity for it: recorded once, never replaced, read back after a reload,
// and never guessed at while the record cannot be read.

import { describe, expect, it, vi } from 'vitest';

import { boundConversation, createConversationVerifier, createPeerBindings } from '../src/domain/peer-bindings.js';
import { createMemoryKv } from '../src/platform/kv.js';

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
});

describe('boundConversation', () => {
  const me = { userId: 'u-alice', handle: 'alice' };
  const listing = (type, members) => ({ id: 'c-1', type, members, disappearingTimerSeconds: 60, lastMessage: { id: 'm-9' } });

  it('keeps the bound peer whatever the listing names, and takes the rest from it', () => {
    const relabelled = boundConversation(listing('direct', [ALICE, MALLORY]), BOB, me);
    expect(relabelled).toMatchObject({ type: 'direct', members: [ALICE, BOB], disappearingTimerSeconds: 60, lastMessage: { id: 'm-9' } });
    expect(boundConversation(listing('group', [ALICE, MALLORY, BOB]), BOB, me)).toMatchObject({ type: 'direct', members: [ALICE, BOB] });
    expect(boundConversation(listing('direct', [ALICE, { userId: 'u-bob', handle: 'mallory' }]), BOB, me).members)
      .toEqual([ALICE, BOB]);
    expect(boundConversation(listing('direct', [MALLORY]), BOB, me).members).toEqual([ALICE, BOB]);
  });

  it('leaves an unbound conversation as listed', () => {
    const listed = listing('direct', [ALICE, MALLORY]);
    expect(boundConversation(listed, null, me)).toBe(listed);
  });
});
