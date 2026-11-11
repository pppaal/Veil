// Trust on first use for Ed25519 identity keys, keyed (userId, deviceId),
// enforced on the directory path and on inbound handshakes alike.

import { describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { DecryptStatus } from '../src/crypto/session-cipher.js';
import { createPinStore, PinVerdict, ReverificationRequiredError } from '../src/crypto/pins.js';
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
    expect(await alice.trust.accept('u-bob')).toBe(true);
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
    await alice.trust.accept('u-bob');
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
    await expect(alice.trust.accept('u-bob')).rejects.toBeInstanceOf(ReverificationRequiredError);
    expect(alice.trust.pendingChange('u-bob')).not.toBeNull();

    await alice.trust.markVerified('u-bob', 'd-bob-2', impostor.device.record.ik.publicKey);
    expect(alice.trust.pendingChange('u-bob')).toBeNull();
    impostor.peers.set(OTHER_CONVERSATION, { userId: 'u-alice', handle: 'alice' });
    expect((await sendText(alice, impostor, 're-verified', OTHER_CONVERSATION)).opened.content.text).toBe('re-verified');
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
