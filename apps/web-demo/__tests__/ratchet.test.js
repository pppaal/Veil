// Security properties of the protocol-v2 sessions: forward secrecy,
// post-compromise recovery, reordering, replay, bounded skipping, durability
// and initiator authentication.

import { describe, expect, it } from 'vitest';

import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { compareBytes, concatBytes } from '../src/crypto/bytes.js';
import { buildFrameAad, decodeFrame, encodeFrameHeader, ENVELOPE_VERSION_V2 } from '../src/crypto/frame.js';
import { deriveMessageKey, kdfRoot } from '../src/crypto/kdf.js';
import { aesGcmSeal, x25519 } from '../src/crypto/keys.js';
import { padMessage } from '../src/crypto/padding.js';
import { encodeInnerPayload } from '../src/crypto/payload-v2.js';
import { MAX_SKIP_PER_STEP, MAX_SKIPPED_KEYS } from '../src/crypto/ratchet.js';
import { DecryptStatus } from '../src/crypto/session-cipher.js';
import { deriveInitiatorKeys, encodePreKeyHeader } from '../src/crypto/x3dh.js';
import { CONVERSATION, connect, createDevice, pair, receive, send, subtle } from './support/devices.js';

async function expectBody(device, envelope, body) {
  const result = await receive(device, envelope);
  expect(result).toMatchObject({ status: DecryptStatus.OK, payload: { body } });
}

async function sendMany(from, to, count, label) {
  const envelopes = [];
  for (let i = 0; i < count; i += 1) envelopes.push(await send(from, to, `${label}${i}`));
  return envelopes;
}

// A second device that holds `victim`'s identity and prekeys, copied as they
// stood when the copy was made, but none of the sessions created later.
async function cloneOf(victim, { sessions = false } = {}) {
  const clone = await createDevice({ userId: victim.userId, deviceId: victim.deviceId, identity: victim.record });
  for (const row of await victim.stores.oneTimePrekeys.all()) await clone.stores.oneTimePrekeys.put(row);
  if (sessions) for (const row of await victim.stores.sessions.all()) await clone.stores.sessions.put(row);
  return clone;
}

describe('protocol v2 ratchet', () => {
  it('stolen identity key cannot decrypt past frames', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    const captured = [];
    captured.push(...await sendMany(alice, bob, 2, 'a'));
    for (const envelope of captured) expect((await receive(bob, envelope)).status).toBe(DecryptStatus.OK);
    const reply = await send(bob, alice, 'b0');
    await expectBody(alice, reply, 'b0');
    captured.push(reply, ...await sendMany(alice, bob, 2, 'later'));
    for (const envelope of captured.slice(3)) expect((await receive(bob, envelope)).status).toBe(DecryptStatus.OK);

    // Later, an attacker takes Bob's identity key, IKx and signed prekey. The
    // one-time prekey was deleted when its session was committed, and the
    // ratchet keys were never part of the identity.
    const thief = await cloneOf(bob);
    expect(await thief.stores.oneTimePrekeys.all()).toEqual([]);
    const outcomes = await Promise.all(captured.map((envelope) => receive(thief, envelope)));
    expect(outcomes.map((outcome) => outcome.status)).not.toContain(DecryptStatus.OK);
    expect(outcomes[0]).toMatchObject({ status: DecryptStatus.FAILED, reason: 'opk_unavailable' });
    expect(outcomes.at(-1).status).toBe(DecryptStatus.SESSION_MISSING);
  });

  it('stolen state locked out after DH step', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    await expectBody(bob, await send(alice, bob, 'hello'), 'hello');
    await expectBody(alice, await send(bob, alice, 'hi'), 'hi');
    const sameChain = await send(alice, bob, 'still on the stolen chain');

    // The attacker copies Bob's whole stored session now.
    const thief = await cloneOf(bob, { sessions: true });
    await expectBody(thief, sameChain, 'still on the stolen chain');
    await expectBody(bob, sameChain, 'still on the stolen chain');

    // Bob replies (a fresh ratchet key), Alice answers with her own: the
    // next chain mixes DH outputs the stolen state cannot compute.
    const bobTurn = await send(bob, alice, 'new turn');
    await expectBody(alice, bobTurn, 'new turn');
    const aliceTurn = await send(alice, bob, 'after the DH step');
    expect((await receive(thief, bobTurn)).status).not.toBe(DecryptStatus.OK);
    expect((await receive(thief, aliceTurn)).status).not.toBe(DecryptStatus.OK);
    await expectBody(bob, aliceTurn, 'after the DH step');
  });

  it('out-of-order 0,3,1,2 decrypt', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    const frames = await sendMany(alice, bob, 4, 'm');
    for (const index of [0, 3, 1, 2]) await expectBody(bob, frames[index], `m${index}`);
  });

  it('late message across DH step decrypts and does not corrupt', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    const [a0, a1, a2] = await sendMany(alice, bob, 3, 'a');
    await expectBody(bob, a0, 'a0');
    await expectBody(alice, await send(bob, alice, 'b0'), 'b0');
    // Alice's next turn carries PN = 3: a1 and a2 are stashed under her old
    // ratchet key before Bob's DH step.
    const a3 = await send(alice, bob, 'a3');
    expect(decodeFrame(decodeBase64Url(a3.ciphertext)).previousCounter).toBe(3);
    await expectBody(bob, a3, 'a3');
    await expectBody(bob, a2, 'a2');
    await expectBody(bob, a1, 'a1');
    for (let turn = 0; turn < 3; turn += 1) {
      await expectBody(alice, await send(bob, alice, `b${turn + 1}`), `b${turn + 1}`);
      await expectBody(bob, await send(alice, bob, `a${turn + 4}`), `a${turn + 4}`);
    }
  });

  it('replay rejected', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    const [first, second] = await sendMany(alice, bob, 2, 'm');
    await expectBody(bob, first, 'm0');
    await expectBody(bob, second, 'm1');
    expect((await receive(bob, first)).status).toBe(DecryptStatus.REPLAYED);
    expect((await receive(bob, second)).status).toBe(DecryptStatus.REPLAYED);

    // A Normal frame from a chain the peer has moved past is a replay too.
    const reply = await send(bob, alice, 'b0');
    await expectBody(alice, reply, 'b0');
    await expectBody(bob, await send(alice, bob, 'a2'), 'a2');
    await expectBody(alice, await send(bob, alice, 'b1'), 'b1');
    expect((await receive(alice, reply)).status).toBe(DecryptStatus.REPLAYED);
  });

  it('skipped cap evicts without blowup', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    const loadOf = async () => (await bob.repo.load(CONVERSATION)).record.current.skipped.size;

    // One frame may stash at most MAX_SKIP_PER_STEP keys.
    const burst = await sendMany(alice, bob, MAX_SKIP_PER_STEP + 2, 'x');
    expect(await receive(bob, burst.at(-1))).toMatchObject({ status: DecryptStatus.FAILED, reason: 'skip_limit' });
    await expectBody(bob, burst.at(-2), `x${MAX_SKIP_PER_STEP}`);
    expect(await loadOf()).toBe(MAX_SKIP_PER_STEP);
    const earliest = burst[0];

    // Turn after turn the session-wide stash stays capped, oldest evicted.
    // (The first turn also stashes the burst's last frame through PN, which
    // counts against the same per-frame budget.)
    for (let turn = 0; turn < 5; turn += 1) {
      await expectBody(alice, await send(bob, alice, `turn${turn}`), `turn${turn}`);
      const frames = await sendMany(alice, bob, MAX_SKIP_PER_STEP, `t${turn}-`);
      await expectBody(bob, frames.at(-1), `t${turn}-${MAX_SKIP_PER_STEP - 1}`);
    }
    expect(await loadOf()).toBe(MAX_SKIPPED_KEYS);
    expect((await receive(bob, earliest)).status).not.toBe(DecryptStatus.OK);
    await expectBody(bob, burst.at(-1), `x${MAX_SKIP_PER_STEP + 1}`);
    expect(await loadOf()).toBe(MAX_SKIPPED_KEYS - 1);
  });

  it('restart restores session', async () => {
    const { alice, bob } = await pair();
    await connect(alice, bob);
    await expectBody(bob, await send(alice, bob, 'before'), 'before');
    const pending = await send(alice, bob, 'in flight');
    alice.restart();
    bob.restart();
    await expectBody(alice, await send(bob, alice, 'after reload'), 'after reload');
    await expectBody(bob, pending, 'in flight');
    await expectBody(bob, await send(alice, bob, 'and on'), 'and on');
    const row = await bob.stores.sessions.get(CONVERSATION);
    // Roots and chains are sealed; only the ratchet private keys are stored
    // as (non-extractable) CryptoKeys.
    expect(Object.keys(row).sort()).toEqual(['conversationId', 'keys', 'nonce', 'rev', 'sealed']);
    expect(row.keys.every((key) => key.extractable === false)).toBe(true);
  });

  it('forged initiator without IK private rejected', async () => {
    const { alice, bob } = await pair();
    const mallory = await createDevice({ userId: 'u-mallory', deviceId: 'd-alice' });
    const target = await bob.directoryEntry();
    const bundleIkx = decodeBase64Url(JSON.parse(new TextDecoder().decode(decodeBase64Url(target.signedPrekeyBundle))).ikx);
    const spk = bob.record.signedPrekeys[0].publicKey;

    // Mallory claims Alice's identity using only Alice's public keys and
    // certificate. DH1 needs Alice's IKx private key, so she substitutes her
    // own; everything else in the frame is genuine.
    const ephemeral = await mallory.keys.x25519();
    const handshake = await deriveInitiatorKeys(subtle, {
      identityEd25519: alice.record.ik.publicKey,
      identityX25519Private: mallory.record.ikx.privateKey,
      identityX25519: alice.record.ikx.publicKey,
      ephemeralPrivate: ephemeral.privateKey,
      remoteIdentityEd25519: target.remoteIdentityKey,
      remoteIdentityX25519: bundleIkx,
      remoteSignedPrekey: spk,
      remoteOneTimePrekey: target.oneTimePrekey.publicKey,
    });
    const ratchet = await mallory.keys.x25519();
    const chain = await kdfRoot(subtle, handshake.sharedKey, await x25519(subtle, ratchet.privateKey, spk));
    const header = encodeFrameHeader({
      preKeyHeader: encodePreKeyHeader({
        identityEd25519: alice.record.ik.publicKey,
        identityX25519: alice.record.ikx.publicKey,
        identityX25519Signature: alice.record.ikx.signature,
        baseKey: ephemeral.publicKey,
        signedPrekeyId: 1,
        oneTimePrekeyId: target.oneTimePrekey.keyId,
      }),
      ratchetPublic: ratchet.publicKey,
      previousCounter: 0,
      counter: 0,
    });
    const nonce = mallory.keys.randomBytes(12);
    const aad = buildFrameAad({
      version: ENVELOPE_VERSION_V2,
      conversationId: CONVERSATION,
      senderDeviceId: 'd-alice',
      messageType: 'text',
      header,
      associatedData: handshake.associatedData,
    });
    const plaintext = padMessage(encodeInnerPayload({ body: 'I am alice', kind: 'text' }));
    const sealed = await aesGcmSeal(subtle, await deriveMessageKey(subtle, chain.chainKey, 0), nonce, plaintext, aad);
    const forged = {
      version: ENVELOPE_VERSION_V2,
      conversationId: CONVERSATION,
      senderDeviceId: 'd-alice',
      messageType: 'text',
      ciphertext: encodeBase64Url(concatBytes([header, sealed])),
      nonce: encodeBase64Url(nonce),
    };

    expect(await receive(bob, forged)).toMatchObject({ status: DecryptStatus.FAILED, reason: 'aead_failed' });
    expect(await bob.cipher.hasSession(CONVERSATION)).toBe(false);
    // Nothing was consumed: the genuine Alice can still use the same prekey.
    await alice.cipher.bootstrap({ conversationId: CONVERSATION, ...target });
    await expectBody(bob, await send(alice, bob, 'really alice'), 'really alice');
  });

  it('OPK used once', async () => {
    const { alice, bob } = await pair();
    const carol = await createDevice({ userId: 'u-carol', deviceId: 'd-carol' });
    const entry = await bob.directoryEntry();
    await alice.cipher.bootstrap({ conversationId: CONVERSATION, ...entry });
    const first = await send(alice, bob, 'first use');
    await expectBody(bob, first, 'first use');
    expect(await bob.stores.oneTimePrekeys.get(entry.oneTimePrekey.keyId)).toBeNull();

    // The same frame again lands on the state it created: a replay, not a
    // second session.
    expect((await receive(bob, first)).status).toBe(DecryptStatus.REPLAYED);
    // A new handshake naming the spent prekey is refused, here and after a
    // restart (the stored row is gone).
    const other = '0d4c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5c';
    await carol.cipher.bootstrap({ conversationId: other, ...entry });
    const reuse = await send(carol, bob, 'reusing', { conversationId: other });
    expect(await receive(bob, reuse)).toMatchObject({ status: DecryptStatus.FAILED, reason: 'opk_unavailable' });
    bob.restart();
    expect(await receive(bob, reuse)).toMatchObject({ status: DecryptStatus.FAILED, reason: 'opk_unavailable' });
    expect(await bob.cipher.hasSession(other)).toBe(false);
  });
});

// Contract C-WEDGE: both clients promote an archived state by the same rule
// (src/crypto/session-record.js #peerAbandonedOurs), so a handshake the peer
// could not open does not leave everything sent on it unreadable.
describe('a handshake the peer could not open', () => {
  // Alice and Bob, with Alice's identity key sorting first or last: glare
  // settles on the handshake of the lower initiator.
  async function orderedPair(aliceFirst) {
    for (;;) {
      const devices = await pair();
      const order = compareBytes(devices.alice.record.ik.publicKey, devices.bob.record.ik.publicKey);
      if ((order < 0) === aliceFirst) return devices;
    }
  }

  for (const aliceFirst of [true, false]) {
    it(`stops holding once the peer keeps sending on its own (${aliceFirst ? 'Alice' : 'Bob'}'s key sorts first)`, async () => {
      const { alice, bob } = await orderedPair(aliceFirst);
      // Alice's handshake names a one-time prekey Bob no longer holds.
      const entry = await connect(alice, bob);
      await bob.stores.oneTimePrekeys.delete(entry.oneTimePrekey.keyId);
      const unopenable = await send(alice, bob, 'a0');
      // Bob, who never received it, starts a handshake of his own.
      await connect(bob, alice);
      const [first, second] = await sendMany(bob, alice, 2, 'b');

      expect(await receive(bob, unopenable)).toMatchObject({ status: DecryptStatus.FAILED, reason: 'opk_unavailable' });
      await expectBody(alice, first, 'b0');
      await expectBody(alice, second, 'b1');
      // Alice now sends on Bob's handshake, and the two converse.
      await expectBody(bob, await send(alice, bob, 'a1'), 'a1');
      await expectBody(alice, await send(bob, alice, 'b2'), 'b2');
      await expectBody(bob, await send(alice, bob, 'a2'), 'a2');
    });
  }

  it('a single competing frame still loses glare to our unanswered handshake', async () => {
    const { alice, bob } = await orderedPair(true);
    await connect(alice, bob);
    const ours = await send(alice, bob, 'a0');
    await connect(bob, alice);
    await expectBody(alice, await send(bob, alice, 'b0'), 'b0');
    // Alice's handshake holds, and Bob, who can open it, settles on it too.
    await expectBody(bob, ours, 'a0');
    await expectBody(bob, await send(alice, bob, 'a1'), 'a1');
    await expectBody(alice, await send(bob, alice, 'b1'), 'b1');
  });
});
