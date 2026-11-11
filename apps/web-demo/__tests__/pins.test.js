// Trust on first use for Ed25519 identity keys, keyed (userId, deviceId),
// enforced on the directory path, on inbound handshakes and on every frame
// sealed or opened alike.

import { describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { compareBytes } from '../src/crypto/bytes.js';
import { DecryptStatus } from '../src/crypto/session-cipher.js';
import { createIdentityTrust, createPinStore, PinVerdict, ReverificationRequiredError } from '../src/crypto/pins.js';
import { claimedOneTimePrekey } from '../src/crypto/prekeys.js';
import { textContent } from '../src/domain/content.js';
import { PeerKeyChangedError } from '../src/features/secure-messaging.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, createEndpoint, directoryEntryOf, serverMessage } from './support/messaging.js';

const OTHER_CONVERSATION = '0d4c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5c';
const key = (byte) => new Uint8Array(32).fill(byte);

async function sendText(from, to, text, conversationId = CONVERSATION) {
  const clientMessageId = `web-${text}`;
  const envelope = await from.secure.seal(conversationId, textContent(text), { clientMessageId });
  const message = serverMessage(envelope, { clientMessageId });
  await from.secure.acknowledge(message);
  return { message, opened: await to.secure.open(message) };
}

// Bob's account on a new identity: the server says it is Bob, same user id.
async function bobReplacement(directory, { deviceId }) {
  const impostor = await createEndpoint({ userId: 'u-bob', deviceId, handle: 'bob', directory });
  directory.set('bob', directoryEntryOf(impostor));
  return impostor;
}

const acceptPending = (endpoint, userId) => endpoint.trust.accept(userId, endpoint.trust.pendingChange(userId));

// The relay answers Alice's first lookup for Bob with a device it holds, so
// trust on first use pins the relay's key. Bob's real device then opens a
// session of its own, and Alice accepts it as a new device, unverified,
// which makes it the device the conversation sends to.
async function relayPinnedFirst() {
  const directory = new Map();
  const alice = await createEndpoint({ userId: 'u-alice', deviceId: 'd-alice', handle: 'alice', directory });
  const relayDevice = await createEndpoint({ userId: 'u-bob', deviceId: 'd-relay', handle: 'bob', directory });
  const bob = await createEndpoint({ userId: 'u-bob', deviceId: 'd-bob', handle: 'bob', directory });
  directory.set('alice', directoryEntryOf(alice));
  directory.set('bob', directoryEntryOf(relayDevice));
  alice.peers.set(CONVERSATION, { userId: 'u-bob', handle: 'bob' });
  for (const endpoint of [relayDevice, bob]) endpoint.peers.set(CONVERSATION, { userId: 'u-alice', handle: 'alice' });

  await sendText(alice, relayDevice, 'to the relay');
  // Answered, so Alice's own handshake no longer holds against Bob's.
  expect((await sendText(relayDevice, alice, 'from the relay')).opened.content.text).toBe('from the relay');

  const genuine = await sendText(bob, alice, 'real bob');
  expect(genuine.opened).toEqual({ failure: DecryptStatus.IDENTITY_REJECTED });
  expect(alice.trust.pendingChange('u-bob'))
    .toMatchObject({ verdict: PinVerdict.NEW_DEVICE, deviceId: 'd-bob', verified: false });
  expect(await acceptPending(alice, 'u-bob')).toBe(true);
  expect((await alice.secure.open(genuine.message)).content.text).toBe('real bob');
  return { alice, bob, relayDevice };
}

// The user compares the safety number the dialog shows and marks it verified.
async function verifyShownKey(alice) {
  const shown = await alice.secure.safetyKey(CONVERSATION);
  await alice.trust.markVerified('u-bob', shown.deviceId, shown.identityKey);
  return shown;
}

describe('identity pins', () => {
  it('pins the first key and reports later matches, changes and new devices', async () => {
    let clock = 0;
    const kv = createMemoryKv('id', { indexField: 'userId' });
    const pins = createPinStore(kv, { now: () => ++clock });
    expect(await pins.check('u-bob', 'd-1', key(1))).toMatchObject({
      verdict: PinVerdict.FIRST_USE,
      pin: { userId: 'u-bob', deviceId: 'd-1', identityKey: encodeBase64Url(key(1)), firstSeenAt: 1, verifiedAt: null },
    });
    expect((await pins.check('u-bob', 'd-1', key(1))).verdict).toBe(PinVerdict.MATCH);
    expect((await pins.check('u-bob', 'd-1', key(2))).verdict).toBe(PinVerdict.CHANGED);
    expect((await pins.check('u-bob', 'd-2', key(2))).verdict).toBe(PinVerdict.NEW_DEVICE);
    expect((await pins.pinsFor('u-bob')).map((pin) => pin.identityKey)).toEqual([encodeBase64Url(key(1))]);
    expect((await pins.check('u-carol', 'd-9', key(9))).verdict).toBe(PinVerdict.FIRST_USE);
  });

  it('a verified contact admits only devices whose own key was verified', async () => {
    const pins = createPinStore(createMemoryKv('id', { indexField: 'userId' }));
    await pins.check('u-bob', 'd-1', key(1));
    await pins.accept('u-bob', 'd-2', key(2));
    expect((await pins.check('u-bob', 'd-1', key(1))).verdict).toBe(PinVerdict.MATCH);

    await pins.markVerified('u-bob', 'd-2', key(2));
    expect(await pins.check('u-bob', 'd-2', key(2))).toMatchObject({ verdict: PinVerdict.MATCH, verified: true });
    // Accepted before the verification, never verified itself.
    expect(await pins.check('u-bob', 'd-1', key(1)))
      .toMatchObject({ verdict: PinVerdict.UNVERIFIED_DEVICE, verified: true });
    await expect(pins.accept('u-bob', 'd-1', key(1))).rejects.toBeInstanceOf(ReverificationRequiredError);

    await pins.markVerified('u-bob', 'd-1', key(1));
    expect((await pins.check('u-bob', 'd-1', key(1))).verdict).toBe(PinVerdict.MATCH);
  });

  it('accepting binds to the change the user reviewed', async () => {
    const pins = createPinStore(createMemoryKv('id', { indexField: 'userId' }));
    const trust = createIdentityTrust({ pins });
    expect(await trust.admit('u-bob', 'd-1', key(1))).toBe(true);
    expect(await trust.admit('u-bob', 'd-2', key(2))).toBe(false);
    const reviewed = trust.pendingChange('u-bob');

    // Another refusal replaces it while the confirmation is open.
    expect(await trust.admit('u-bob', 'd-3', key(3))).toBe(false);
    expect(await trust.accept('u-bob', reviewed)).toBe(false);
    expect((await pins.pinsFor('u-bob')).map((pin) => pin.deviceId)).toEqual(['d-1']);
    expect(trust.pendingChange('u-bob')).toMatchObject({ deviceId: 'd-3' });

    expect(await trust.accept('u-bob', trust.pendingChange('u-bob'))).toBe(true);
    expect((await pins.pinsFor('u-bob')).map((pin) => pin.deviceId)).toEqual(['d-1', 'd-3']);
    expect(await trust.accept('u-bob', reviewed)).toBe(false);
  });

  it('the safety key is a pending change, else the session identity, else the newest pin', async () => {
    let clock = 0;
    const pins = createPinStore(createMemoryKv('id', { indexField: 'userId' }), { now: () => ++clock });
    const trust = createIdentityTrust({ pins });
    expect(await trust.safetyKey('u-bob', null)).toBeNull();
    await trust.admit('u-bob', 'd-1', key(1));
    await pins.accept('u-bob', 'd-2', key(2));

    const session = { remoteDeviceId: 'd-1', remoteIdentityKey: key(1) };
    expect(await trust.safetyKey('u-bob', session))
      .toEqual({ deviceId: 'd-1', identityKey: key(1), pendingVerdict: null, verified: false });
    // Only before there is a session does the newest pin stand in.
    expect(await trust.safetyKey('u-bob', null)).toMatchObject({ deviceId: 'd-2', identityKey: key(2) });

    await trust.markVerified('u-bob', 'd-1', key(1));
    expect(await trust.safetyKey('u-bob', session)).toMatchObject({ deviceId: 'd-1', verified: true });
    // A session bound to another key than the device's pin is not verified.
    expect(await trust.safetyKey('u-bob', { remoteDeviceId: 'd-1', remoteIdentityKey: key(9) }))
      .toMatchObject({ identityKey: key(9), verified: false });

    expect(await trust.admit('u-bob', 'd-2', key(2))).toBe(false);
    expect(await trust.safetyKey('u-bob', session)).toEqual({
      deviceId: 'd-2',
      identityKey: key(2),
      pendingVerdict: PinVerdict.UNVERIFIED_DEVICE,
      verified: false,
    });
  });

  it('first contacts racing for one user pin only one of them', async () => {
    const kv = createMemoryKv('id', { indexField: 'userId' });
    const pins = createPinStore(kv);
    // Two handshakes in two conversations, each under its own conversation lock.
    const verdicts = await Promise.all([pins.check('u-bob', 'd-1', key(1)), pins.check('u-bob', 'd-2', key(2))]);
    expect(verdicts.map((result) => result.verdict)).toEqual([PinVerdict.FIRST_USE, PinVerdict.NEW_DEVICE]);
    expect((await pins.pinsFor('u-bob')).map((pin) => pin.deviceId)).toEqual(['d-1']);
  });

  it('changed peer key freezes sending until accepted', async () => {
    const { alice, bob, directory } = await conversation();
    expect((await sendText(alice, bob, 'hello')).opened.content.text).toBe('hello');

    // The directory now serves another identity for Bob, in a conversation
    // Alice has no session in yet.
    const impostor = await bobReplacement(directory, { deviceId: 'd-bob' });
    alice.peers.set(OTHER_CONVERSATION, { userId: 'u-bob', handle: 'bob' });
    impostor.peers.set(OTHER_CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    await expect(alice.secure.seal(OTHER_CONVERSATION, textContent('x'), { clientMessageId: 'c1' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(alice.keyChanges).toEqual(['u-bob']);
    expect(alice.trust.pendingChange('u-bob')).toMatchObject({ verdict: PinVerdict.CHANGED, deviceId: 'd-bob' });
    // Frozen everywhere with Bob, the established conversation included.
    await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: 'c2' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect((await createPinStore(alice.pinKv).pinsFor('u-bob'))[0].identityKey)
      .toBe(encodeBase64Url(bob.device.record.ik.publicKey));

    // Explicit acceptance re-pins and unfreezes; the new key is the one used.
    expect(await acceptPending(alice, 'u-bob')).toBe(true);
    expect(alice.trust.pendingChange('u-bob')).toBeNull();
    expect((await createPinStore(alice.pinKv).pinsFor('u-bob'))[0].identityKey)
      .toBe(encodeBase64Url(impostor.device.record.ik.publicKey));
    expect((await sendText(alice, impostor, 'accepted', OTHER_CONVERSATION)).opened.content.text).toBe('accepted');
  });

  it('inbound handshake from a changed identity is rejected and stores nothing', async () => {
    const { alice, bob, directory } = await conversation();
    expect((await sendText(bob, alice, 'genuine')).opened.content.text).toBe('genuine');
    const before = await alice.device.stores.sessions.get(CONVERSATION);

    // A relay that holds another identity opens a session to Alice as Bob's
    // device: the handshake authenticates, the identity does not match.
    const impostor = await bobReplacement(directory, { deviceId: 'd-bob' });
    impostor.peers.set(CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    const envelope = await impostor.secure.seal(CONVERSATION, textContent('trust me'), { clientMessageId: 'i-1' });
    const message = serverMessage(envelope, { clientMessageId: 'i-1' });
    const opkCount = (await alice.device.stores.oneTimePrekeys.all()).length;
    expect(await alice.secure.open(message)).toEqual({ failure: DecryptStatus.IDENTITY_REJECTED });
    expect(alice.trust.pendingChange('u-bob')).toMatchObject({ verdict: PinVerdict.CHANGED });
    expect(await alice.device.stores.sessions.get(CONVERSATION)).toEqual(before);
    expect((await alice.device.stores.oneTimePrekeys.all()).length).toBe(opkCount);
    expect(await alice.contentStore.get(CONVERSATION, message.id)).toBeNull();
    await expect(alice.secure.seal(CONVERSATION, textContent('reply'), { clientMessageId: 'r' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);

    // Once the user accepts the change, the same frame opens.
    await acceptPending(alice, 'u-bob');
    expect((await alice.secure.open(message)).content.text).toBe('trust me');
  });

  it('verified contact key change requires reverification', async () => {
    const { alice, bob, directory } = await conversation();
    await sendText(alice, bob, 'hello');
    await alice.trust.markVerified('u-bob', 'd-bob', bob.device.record.ik.publicKey);
    const impostor = await bobReplacement(directory, { deviceId: 'd-bob-2' });
    alice.peers.set(OTHER_CONVERSATION, { userId: 'u-bob', handle: 'bob' });
    await expect(alice.secure.seal(OTHER_CONVERSATION, textContent('x'), { clientMessageId: 'c1' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(alice.trust.pendingChange('u-bob')).toMatchObject({ verdict: PinVerdict.NEW_DEVICE, verified: true });
    await expect(acceptPending(alice, 'u-bob')).rejects.toBeInstanceOf(ReverificationRequiredError);
    expect(alice.trust.pendingChange('u-bob')).not.toBeNull();

    await alice.trust.markVerified('u-bob', 'd-bob-2', impostor.device.record.ik.publicKey);
    expect(alice.trust.pendingChange('u-bob')).toBeNull();
    impostor.peers.set(OTHER_CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    expect((await sendText(alice, impostor, 're-verified', OTHER_CONVERSATION)).opened.content.text).toBe('re-verified');
  });

  it('the safety number is about the device the session sends to, not the newest pin', async () => {
    const { alice, bob, directory } = await conversation();
    await sendText(alice, bob, 'hello');
    // A second device of Bob's, accepted in another conversation, is the
    // newest pin; this conversation still sends to the first.
    const second = await bobReplacement(directory, { deviceId: 'd-bob-2' });
    alice.peers.set(OTHER_CONVERSATION, { userId: 'u-bob', handle: 'bob' });
    second.peers.set(OTHER_CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    await expect(alice.secure.seal(OTHER_CONVERSATION, textContent('x'), { clientMessageId: 'c1' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(await acceptPending(alice, 'u-bob')).toBe(true);
    await sendText(alice, second, 'to the second device', OTHER_CONVERSATION);

    const shown = await alice.secure.safetyKey(CONVERSATION);
    expect({ ...shown, identityKey: encodeBase64Url(shown.identityKey) }).toEqual({
      deviceId: 'd-bob',
      identityKey: encodeBase64Url(bob.device.record.ik.publicKey),
      pendingVerdict: null,
      verified: false,
    });
    const other = await alice.secure.safetyKey(OTHER_CONVERSATION);
    expect(encodeBase64Url(other.identityKey)).toBe(encodeBase64Url(second.device.record.ik.publicKey));

    // Verifying what the dialog shows verifies that device and no other.
    await verifyShownKey(alice);
    expect((await sendText(alice, bob, 'verified')).opened.content.text).toBe('verified');
    await expect(alice.secure.safetyKey(OTHER_CONVERSATION))
      .resolves.toMatchObject({ deviceId: 'd-bob-2', verified: false });
  });

  it('a device accepted before verification cannot take the conversation back with a new handshake', async () => {
    const { alice, bob, relayDevice } = await relayPinnedFirst();
    const shown = await verifyShownKey(alice);
    expect({ deviceId: shown.deviceId, identityKey: encodeBase64Url(shown.identityKey) })
      .toEqual({ deviceId: 'd-bob', identityKey: encodeBase64Url(bob.device.record.ik.publicKey) });

    // The relay opens a fresh session from the device Alice pinned first.
    const aliceEntry = await alice.device.directoryEntry();
    await relayDevice.device.cipher.bootstrap({ conversationId: CONVERSATION, ...aliceEntry });
    const before = await alice.device.stores.sessions.get(CONVERSATION);
    const opkCount = (await alice.device.stores.oneTimePrekeys.all()).length;
    const hijack = await sendText(relayDevice, alice, 'relay again');
    expect(hijack.opened).toEqual({ failure: DecryptStatus.IDENTITY_REJECTED });
    expect(alice.trust.pendingChange('u-bob'))
      .toMatchObject({ verdict: PinVerdict.UNVERIFIED_DEVICE, deviceId: 'd-relay', verified: true });
    await expect(acceptPending(alice, 'u-bob')).rejects.toBeInstanceOf(ReverificationRequiredError);
    expect(await alice.device.stores.sessions.get(CONVERSATION)).toEqual(before);
    expect((await alice.device.stores.oneTimePrekeys.all()).length).toBe(opkCount);
    await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: 'frozen' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);

    // Pending changes do not survive a reload; the session still runs on the
    // verified device and the dialog says so.
    alice.restart();
    await expect(alice.secure.safetyKey(CONVERSATION)).resolves.toMatchObject({ deviceId: 'd-bob', verified: true });
    expect((await sendText(alice, bob, 'still bob')).opened.content.text).toBe('still bob');
  });

  it('frames on an earlier session of a device accepted before verification are refused', async () => {
    const { alice, relayDevice } = await relayPinnedFirst();
    // Before the verification, the relay's earlier session still reads.
    expect((await sendText(relayDevice, alice, 'accepted device')).opened.content.text).toBe('accepted device');

    await verifyShownKey(alice);
    const before = await alice.device.stores.sessions.get(CONVERSATION);
    const late = await sendText(relayDevice, alice, 'after verification');
    expect(late.opened).toEqual({ failure: DecryptStatus.IDENTITY_REJECTED });
    expect(alice.trust.pendingChange('u-bob'))
      .toMatchObject({ verdict: PinVerdict.UNVERIFIED_DEVICE, deviceId: 'd-relay', verified: true });
    expect(await alice.device.stores.sessions.get(CONVERSATION)).toEqual(before);
    expect(await alice.contentStore.get(CONVERSATION, late.message.id)).toBeNull();

    // Should the user verify that device after all, the same frame opens.
    await alice.trust.markVerified('u-bob', 'd-relay', relayDevice.device.record.ik.publicKey);
    expect((await alice.secure.open(late.message)).content.text).toBe('after verification');
  });

  it('sending stops once the contact is verified on another device, until this one is verified too', async () => {
    const { alice, bob } = await conversation();
    await sendText(alice, bob, 'hello');
    // The user compared the safety number of another device of Bob's.
    await alice.trust.markVerified('u-bob', 'd-bob-2', key(7));
    const before = await alice.device.stores.sessions.get(CONVERSATION);

    await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: 'c1' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(alice.trust.pendingChange('u-bob'))
      .toMatchObject({ verdict: PinVerdict.UNVERIFIED_DEVICE, deviceId: 'd-bob', verified: true });
    expect(await alice.device.stores.sessions.get(CONVERSATION)).toEqual(before);
    expect(await alice.contentStore.get(CONVERSATION, 'client:c1')).toBeNull();

    // The dialog shows this device's key, pending; verifying it resumes.
    const shown = await verifyShownKey(alice);
    expect(encodeBase64Url(shown.identityKey)).toBe(encodeBase64Url(bob.device.record.ik.publicKey));
    expect((await sendText(alice, bob, 'verified both')).opened.content.text).toBe('verified both');
  });

  it('a relay that never answers keeps no hold on a conversation the user verified', async () => {
    // Alice's handshake to the relay stays unanswered, so it wins the glare
    // tie-break against Bob's handshake when Bob's key sorts after hers:
    // Bob's state is archived and the conversation stays on the relay's.
    const directory = new Map();
    const alice = await createEndpoint({ userId: 'u-alice', deviceId: 'd-alice', handle: 'alice', directory });
    let bob;
    do {
      bob = await createEndpoint({ userId: 'u-bob', deviceId: 'd-bob', handle: 'bob', directory });
    } while (compareBytes(bob.device.record.ik.publicKey, alice.device.record.ik.publicKey) < 0);
    const relayDevice = await createEndpoint({ userId: 'u-bob', deviceId: 'd-relay', handle: 'bob', directory });
    directory.set('alice', directoryEntryOf(alice));
    directory.set('bob', directoryEntryOf(relayDevice));
    alice.peers.set(CONVERSATION, { userId: 'u-bob', handle: 'bob' });
    bob.peers.set(CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    await alice.secure.seal(CONVERSATION, textContent('to the relay'), { clientMessageId: 'r1' });

    const genuine = await sendText(bob, alice, 'real bob');
    expect(genuine.opened).toEqual({ failure: DecryptStatus.IDENTITY_REJECTED });
    // The user compares Bob's number and verifies it; his frame then opens.
    const shown = await verifyShownKey(alice);
    expect(shown).toMatchObject({ deviceId: 'd-bob', pendingVerdict: PinVerdict.NEW_DEVICE });
    expect((await alice.secure.open(genuine.message)).content.text).toBe('real bob');

    // The dialog names the device the conversation sends to, unverified...
    await expect(alice.secure.safetyKey(CONVERSATION)).resolves.toMatchObject({ deviceId: 'd-relay', verified: false });
    // ...and nothing more is sealed to it.
    await expect(alice.secure.seal(CONVERSATION, textContent('secret'), { clientMessageId: 'r2' }))
      .rejects.toBeInstanceOf(PeerKeyChangedError);
    expect(alice.trust.pendingChange('u-bob'))
      .toMatchObject({ verdict: PinVerdict.UNVERIFIED_DEVICE, deviceId: 'd-relay', verified: true });
  });

  it('no refetch after decrypt failures', async () => {
    const { alice, bob } = await conversation();
    const { message } = await sendText(bob, alice, 'genuine');
    expect(alice.lookups).toBe(0);
    expect(bob.lookups).toBe(1);

    const bytes = message.ciphertext;
    const flip = (text) => text.slice(0, -2) + (text.endsWith('AA') ? 'BB' : 'AA');
    const attempts = [
      { ciphertext: flip(bytes) },
      { ciphertext: 'AgI' },
      { ciphertext: '!!!' },
      { nonce: 'AAAAAAAAAAAAAAAA' },
      { senderDeviceId: 'd-mallory' },
      { messageType: 'image' },
    ];
    for (const [index, overrides] of attempts.entries()) {
      const tampered = { ...message, id: `forged-${index}`, ...overrides };
      expect((await alice.secure.open(tampered)).failure).toBeDefined();
    }
    expect(alice.lookups).toBe(0);
    expect(bob.lookups).toBe(1);
    expect((await alice.secure.open(message)).content.text).toBe('genuine');
    // Replies go out on the session the handshake opened: still no lookup.
    await sendText(alice, bob, 'reply');
    expect(alice.lookups).toBe(0);
  });

  it('pins nothing for a key whose bundle does not verify', async () => {
    const { alice, directory } = await conversation();
    // A peer whose client predates protocol v2 publishes its X25519 key and
    // no v2 bundle.
    directory.set('bob', async () => ({
      deviceId: 'd-bob',
      identityKey: key(7),
      signedPrekeyBundle: 'web-demo-no-prekey',
      oneTimePrekey: null,
    }));
    await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: 'c1' }))
      .rejects.toMatchObject({ name: 'PeerUnavailableError', reason: 'not-upgraded' });
    expect(await createPinStore(alice.pinKv).pinsFor('u-bob')).toEqual([]);
    expect(alice.trust.pendingChange('u-bob')).toBeNull();
  });

  it('rejects a bundle whose claimed one-time prekey is malformed', async () => {
    const { alice, bob, directory } = await conversation();
    const serve = directoryEntryOf(bob);
    const malformed = [
      { keyId: 1, publicKey: 'not base64url!' },
      { keyId: -1, publicKey: encodeBase64Url(key(3)) },
      { keyId: 1, publicKey: encodeBase64Url(new Uint8Array(31)) },
    ];
    for (const [index, raw] of malformed.entries()) {
      // As app.js reads GET /v1/keys/:handle: the claimed prekey is checked there.
      directory.set('bob', async () => ({ ...(await serve()), oneTimePrekey: claimedOneTimePrekey(raw) }));
      await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: `c${index}` }))
        .rejects.toMatchObject({ name: 'PeerUnavailableError', reason: 'bad-bundle' });
    }
    expect(await createPinStore(alice.pinKv).pinsFor('u-bob')).toEqual([]);
  });

  it('retries an unreachable directory but not a resolved key', async () => {
    const { alice, bob, directory } = await conversation();
    let offline = true;
    const serve = directoryEntryOf(bob);
    directory.set('bob', async () => {
      if (offline) throw new Error('offline');
      return serve();
    });
    await expect(alice.secure.seal(CONVERSATION, textContent('x'), { clientMessageId: 'c1' })).rejects.toThrow('offline');
    offline = false;
    await sendText(alice, bob, 'online');
    await sendText(alice, bob, 'again');
    expect(alice.lookups).toBe(2);
  });
});
