// Reproduces every protocolV2 vector of packages/shared/test-vectors/
// crypto-kat.json byte for byte: the vectors the mobile client and the
// independent node:crypto generator (scripts/crypto-test-vectors.mjs) pin.

import { describe, expect, it } from 'vitest';
import { hkdfSync, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { decryptAttachment, encryptAttachment } from '../src/crypto/attachment-v2.js';
import { BundleError, createIdentityKeys, verifyBundle } from '../src/crypto/bundle.js';
import { buildFrameAad, decodeFrame, ENVELOPE_VERSION_V2 } from '../src/crypto/frame.js';
import { deriveMessageKey, kdfRoot } from '../src/crypto/kdf.js';
import { generateStorageKey, x25519 } from '../src/crypto/keys.js';
import { padMessage, padmeLength } from '../src/crypto/padding.js';
import { decodeInnerPayload, encodeInnerPayload } from '../src/crypto/payload-v2.js';
import { DecryptStatus } from '../src/crypto/session-cipher.js';
import {
  decodePreKeyHeader,
  deriveInitiatorKeys,
  deriveResponderKeys,
  encodePreKeyHeader,
  NO_ONE_TIME_PREKEY_ID,
} from '../src/crypto/x3dh.js';
import { createDevice } from './support/devices.js';
import { ed25519FromHex, fromHex, scriptedKeySource, toHex, x25519FromHex } from './support/keys.js';

const { subtle } = webcrypto;
const KAT = JSON.parse(
  readFileSync(new URL('../../../packages/shared/test-vectors/crypto-kat.json', import.meta.url), 'utf8'),
).vectors.protocolV2;
const { bundle: BUNDLE, oneTimePrekey: OPK, alice: ALICE, x3dh: X3DH, frames: FRAMES } = KAT;
const MESSAGES = Object.fromEntries(FRAMES.messages.map((message) => [message.label, message]));
const CLOCK = () => ALICE.clockMs;

const payloadOf = (message) => {
  const parsed = JSON.parse(message.innerPayloadJson);
  return { body: parsed.b, kind: parsed.k, expiresAt: parsed.x, attachment: parsed.att };
};

const envelopeOf = (message) => ({
  version: KAT.constants.envelopeVersion,
  conversationId: FRAMES.conversationId,
  senderDeviceId: message.senderDeviceId,
  messageType: message.messageKind,
  ciphertext: message.envelopeCiphertext,
  nonce: message.envelopeNonce,
});

async function vectorIdentity({ seed, ikxPrivate, ikxSignature, spkPrivate, spkTs }) {
  const spk = await x25519FromHex(spkPrivate);
  return {
    ik: await ed25519FromHex(seed),
    ikx: { ...(await x25519FromHex(ikxPrivate)), signature: fromHex(ikxSignature) },
    signedPrekeys: [{ id: 1, ...spk, createdAt: spkTs, publishedAt: spkTs, supersededAt: null }],
    nextOneTimePrekeyId: 2,
    sessionKek: await generateStorageKey(subtle),
  };
}

// Alice draws EK, her first ratchet key, then her send-step key; Bob draws
// his send-step key. Nonces are drawn one per encrypt, in sending order.
async function vectorDevices() {
  const alice = await createDevice({
    userId: 'u-alice',
    deviceId: FRAMES.aliceDeviceId,
    clock: CLOCK,
    identity: await vectorIdentity({
      seed: ALICE.identitySeed,
      ikxPrivate: ALICE.ikxPrivate,
      ikxSignature: ALICE.ikxSignature,
      spkPrivate: ALICE.spkPrivate,
      spkTs: BUNDLE.spkTs,
    }),
    keys: scriptedKeySource({
      x25519: [X3DH.ephemeralPrivate, KAT.ratchetInit.aliceRatchetPrivate, KAT.sendSteps.alice.ratchetPrivate],
      randomBytes: ['A0', 'A1', 'A2'].map((label) => MESSAGES[label].nonce),
    }),
  });
  const bob = await createDevice({
    userId: 'u-bob',
    deviceId: FRAMES.bobDeviceId,
    clock: CLOCK,
    identity: await vectorIdentity({
      seed: BUNDLE.identitySeed,
      ikxPrivate: BUNDLE.ikxPrivate,
      ikxSignature: BUNDLE.ikxSignature,
      spkPrivate: BUNDLE.spkPrivate,
      spkTs: BUNDLE.spkTs,
    }),
    keys: scriptedKeySource({ x25519: [KAT.sendSteps.bob.ratchetPrivate], randomBytes: [MESSAGES.B0.nonce] }),
  });
  const opk = await x25519FromHex(OPK.private);
  await bob.stores.oneTimePrekeys.put({ keyId: OPK.keyId, ...opk });
  return { alice, bob };
}

const encrypt = (device, message) => device.cipher.encrypt({
  conversationId: FRAMES.conversationId,
  senderDeviceId: message.senderDeviceId,
  recipientUserId: 'u-peer',
  payload: payloadOf(message),
});

async function expectDecrypts(device, message) {
  const result = await device.cipher.decrypt(envelopeOf(message));
  expect(result.status).toBe(DecryptStatus.OK);
  expect(result.payload).toEqual({ ...payloadOf(message), replyTo: null });
}

describe('protocol v2 known answers', () => {
  it('bundle: C1 vector, identity key and signatures', async () => {
    const keys = scriptedKeySource({ ed25519: [BUNDLE.identitySeed], x25519: [BUNDLE.ikxPrivate, BUNDLE.spkPrivate] });
    const identity = await createIdentityKeys(subtle, keys, BUNDLE.spkTs);
    expect(identity.bundle).toBe(BUNDLE.signedPrekeyBundle);
    expect(new TextDecoder().decode(decodeBase64Url(identity.bundle))).toBe(BUNDLE.bundleJson);
    expect(encodeBase64Url(identity.ik.publicKey)).toBe(BUNDLE.identityPublicKey);
    expect(toHex(identity.ikx.publicKey)).toBe(BUNDLE.ikxPublic);
    expect(toHex(identity.ikxSig)).toBe(BUNDLE.ikxSignature);
    expect(toHex(identity.spk.publicKey)).toBe(BUNDLE.spkPublic);

    const verified = await verifyBundle(subtle, BUNDLE.signedPrekeyBundle, fromHex(BUNDLE.identityPublic), { nowMs: ALICE.clockMs });
    expect({ ikx: toHex(verified.ikx), spk: toHex(verified.spk), spkId: verified.spkId, spkTs: verified.spkTs })
      .toEqual({ ikx: BUNDLE.ikxPublic, spk: BUNDLE.spkPublic, spkId: BUNDLE.spkId, spkTs: BUNDLE.spkTs });

    const swapped = JSON.parse(BUNDLE.bundleJson);
    swapped.spk = encodeBase64Url(fromHex(OPK.public));
    const forged = encodeBase64Url(new TextEncoder().encode(JSON.stringify(swapped)));
    await expect(verifyBundle(subtle, forged, fromHex(BUNDLE.identityPublic), { nowMs: ALICE.clockMs }))
      .rejects.toMatchObject({ reason: 'bad_signature' });
    await expect(verifyBundle(subtle, BUNDLE.signedPrekeyBundle, fromHex(BUNDLE.identityPublic), {
      nowMs: BUNDLE.spkTs + 61 * 24 * 3600 * 1000,
    })).rejects.toMatchObject({ reason: 'stale' });
    await expect(verifyBundle(subtle, 'web-demo-no-prekey', fromHex(BUNDLE.identityPublic), { nowMs: ALICE.clockMs }))
      .rejects.toBeInstanceOf(BundleError);
  });

  it('X3DH with OPK: DH outputs, shared key, AD and PreKey header', async () => {
    const aliceIk = await ed25519FromHex(ALICE.identitySeed);
    const aliceIkx = await x25519FromHex(ALICE.ikxPrivate);
    const ek = await x25519FromHex(X3DH.ephemeralPrivate);
    const bobIkx = await x25519FromHex(BUNDLE.ikxPrivate);
    const spk = await x25519FromHex(BUNDLE.spkPrivate);
    const opk = await x25519FromHex(OPK.private);

    expect(toHex(await x25519(subtle, aliceIkx.privateKey, spk.publicKey))).toBe(X3DH.dh1);
    expect(toHex(await x25519(subtle, ek.privateKey, bobIkx.publicKey))).toBe(X3DH.dh2);
    expect(toHex(await x25519(subtle, ek.privateKey, spk.publicKey))).toBe(X3DH.dh3);
    expect(toHex(await x25519(subtle, ek.privateKey, opk.publicKey))).toBe(X3DH.dh4);

    const initiator = await deriveInitiatorKeys(subtle, {
      identityEd25519: aliceIk.publicKey,
      identityX25519Private: aliceIkx.privateKey,
      identityX25519: aliceIkx.publicKey,
      ephemeralPrivate: ek.privateKey,
      remoteIdentityEd25519: fromHex(BUNDLE.identityPublic),
      remoteIdentityX25519: bobIkx.publicKey,
      remoteSignedPrekey: spk.publicKey,
      remoteOneTimePrekey: opk.publicKey,
    });
    expect(toHex(initiator.sharedKey)).toBe(X3DH.sharedKey);
    expect(toHex(initiator.associatedData)).toBe(X3DH.associatedData);

    const header = encodePreKeyHeader({
      identityEd25519: aliceIk.publicKey,
      identityX25519: aliceIkx.publicKey,
      identityX25519Signature: fromHex(ALICE.ikxSignature),
      baseKey: ek.publicKey,
      signedPrekeyId: BUNDLE.spkId,
      oneTimePrekeyId: OPK.keyId,
    });
    expect(toHex(header)).toBe(X3DH.preKeyHeader);

    const responder = await deriveResponderKeys(subtle, {
      header: decodePreKeyHeader(fromHex(X3DH.preKeyHeader)),
      identityEd25519: fromHex(BUNDLE.identityPublic),
      identityX25519Private: bobIkx.privateKey,
      identityX25519: bobIkx.publicKey,
      signedPrekeyPrivate: spk.privateKey,
      oneTimePrekeyPrivate: opk.privateKey,
    });
    expect(toHex(responder.sharedKey)).toBe(X3DH.sharedKey);
    expect(toHex(responder.associatedData)).toBe(X3DH.associatedData);
  });

  it('X3DH without OPK: both sides agree on HKDF over DH1..DH3 only', async () => {
    const aliceIk = await ed25519FromHex(ALICE.identitySeed);
    const aliceIkx = await x25519FromHex(ALICE.ikxPrivate);
    const ek = await x25519FromHex(X3DH.ephemeralPrivate);
    const bobIkx = await x25519FromHex(BUNDLE.ikxPrivate);
    const spk = await x25519FromHex(BUNDLE.spkPrivate);
    // The KAT pins the four-DH secret; the three-DH one is the same HKDF
    // with DH4 left out, computed here with node:crypto.
    const expected = toHex(hkdfSync(
      'sha256',
      fromHex('ff'.repeat(32) + X3DH.dh1 + X3DH.dh2 + X3DH.dh3),
      fromHex(X3DH.salt),
      fromHex(X3DH.info),
      32,
    ));

    const initiator = await deriveInitiatorKeys(subtle, {
      identityEd25519: aliceIk.publicKey,
      identityX25519Private: aliceIkx.privateKey,
      identityX25519: aliceIkx.publicKey,
      ephemeralPrivate: ek.privateKey,
      remoteIdentityEd25519: fromHex(BUNDLE.identityPublic),
      remoteIdentityX25519: bobIkx.publicKey,
      remoteSignedPrekey: spk.publicKey,
    });
    const header = decodePreKeyHeader(encodePreKeyHeader({
      identityEd25519: aliceIk.publicKey,
      identityX25519: aliceIkx.publicKey,
      identityX25519Signature: fromHex(ALICE.ikxSignature),
      baseKey: ek.publicKey,
      signedPrekeyId: BUNDLE.spkId,
      oneTimePrekeyId: NO_ONE_TIME_PREKEY_ID,
    }));
    expect(header.oneTimePrekeyId).toBe(KAT.constants.noOneTimePrekeyId);
    const responder = await deriveResponderKeys(subtle, {
      header,
      identityEd25519: fromHex(BUNDLE.identityPublic),
      identityX25519Private: bobIkx.privateKey,
      identityX25519: bobIkx.publicKey,
      signedPrekeyPrivate: spk.privateKey,
    });
    expect(toHex(initiator.sharedKey)).toBe(expected);
    expect(toHex(responder.sharedKey)).toBe(expected);
    expect(expected).not.toBe(X3DH.sharedKey);
    expect(toHex(initiator.associatedData)).toBe(X3DH.associatedData);
  });

  it('ratchet KDF chain: init, both send steps and every message key', async () => {
    const init = await kdfRoot(subtle, fromHex(X3DH.sharedKey), fromHex(KAT.ratchetInit.dhOutput));
    expect(toHex(init.rootKey)).toBe(KAT.ratchetInit.rootKey);
    expect(toHex(init.chainKey)).toBe(KAT.ratchetInit.sendChainKey);
    const bobStep = await kdfRoot(subtle, init.rootKey, fromHex(KAT.sendSteps.bob.dhOutput));
    expect(toHex(bobStep.rootKey)).toBe(KAT.sendSteps.bob.rootKey);
    expect(toHex(bobStep.chainKey)).toBe(KAT.sendSteps.bob.chainKey);
    const aliceStep = await kdfRoot(subtle, bobStep.rootKey, fromHex(KAT.sendSteps.alice.dhOutput));
    expect(toHex(aliceStep.rootKey)).toBe(KAT.sendSteps.alice.rootKey);
    expect(toHex(aliceStep.chainKey)).toBe(KAT.sendSteps.alice.chainKey);
    for (const message of FRAMES.messages) {
      expect(toHex(await deriveMessageKey(subtle, fromHex(message.chainKey), message.counter))).toBe(message.messageKey);
    }
  });

  it('frames: first PreKey frame, Normal frame after a turn and the PN straggler, byte for byte', async () => {
    const { alice, bob } = await vectorDevices();
    await alice.cipher.bootstrap({
      conversationId: FRAMES.conversationId,
      remoteDeviceId: FRAMES.bobDeviceId,
      remoteIdentityKey: fromHex(BUNDLE.identityPublic),
      signedPrekeyBundle: BUNDLE.signedPrekeyBundle,
      oneTimePrekey: { keyId: OPK.keyId, publicKey: fromHex(OPK.public) },
    });
    for (const label of ['A0', 'A1']) {
      expect(await encrypt(alice, MESSAGES[label])).toMatchObject({
        version: ENVELOPE_VERSION_V2,
        ciphertext: MESSAGES[label].envelopeCiphertext,
        nonce: MESSAGES[label].envelopeNonce,
        messageType: 'text',
      });
    }

    // Bob receives A0, A2, then A1.
    await expectDecrypts(bob, MESSAGES.A0);
    expect(await bob.stores.oneTimePrekeys.get(OPK.keyId)).toBeNull();
    expect((await encrypt(bob, MESSAGES.B0)).ciphertext).toBe(MESSAGES.B0.envelopeCiphertext);
    await expectDecrypts(alice, MESSAGES.B0);
    const a2 = await encrypt(alice, MESSAGES.A2);
    expect(a2).toMatchObject({ ciphertext: MESSAGES.A2.envelopeCiphertext, nonce: MESSAGES.A2.envelopeNonce, messageType: 'file' });
    await expectDecrypts(bob, MESSAGES.A2);
    await expectDecrypts(bob, MESSAGES.A1);
  });

  it('AAD and frame layout of every message', () => {
    for (const message of FRAMES.messages) {
      const frame = decodeFrame(fromHex(message.frame));
      expect(toHex(frame.header)).toBe(message.header);
      expect(toHex(frame.ratchetPublic)).toBe(message.ratchetPublic);
      expect(frame.previousCounter).toBe(message.previousCounter);
      expect(frame.counter).toBe(message.counter);
      expect(toHex(frame.sealed)).toBe(message.ciphertext + message.tag);
      expect(frame.preKey === null).toBe(message.frameType === 'normal');
      const aad = buildFrameAad({
        version: KAT.constants.envelopeVersion,
        conversationId: FRAMES.conversationId,
        senderDeviceId: message.senderDeviceId,
        messageType: message.messageKind,
        header: frame.header,
        associatedData: fromHex(X3DH.associatedData),
      });
      expect(toHex(aad)).toBe(message.aad);
    }
  });

  it('inner payload and its padding', () => {
    for (const message of FRAMES.messages) {
      const encoded = encodeInnerPayload(payloadOf(message));
      expect(new TextDecoder().decode(encoded)).toBe(message.innerPayloadJson);
      expect(toHex(padMessage(encoded))).toBe(message.paddedPlaintext);
      expect(decodeInnerPayload(encoded, { fallbackKind: 'text' })).toEqual({ ...payloadOf(message), replyTo: null });
    }
  });

  it('Padmé table', () => {
    for (const { n, padme } of KAT.padme) expect(padmeLength(n)).toBe(padme);
  });

  it('attachment blob, digest and pointer', async () => {
    const vector = KAT.attachment;
    const draws = [vector.key, vector.nonce];
    const randomBytes = (length) => {
      const bytes = fromHex(draws.shift());
      expect(bytes).toHaveLength(length);
      return bytes;
    };
    const plaintext = fromHex(vector.plaintextHex);
    const { pointer, blob } = await encryptAttachment(subtle, randomBytes, {
      attachmentId: vector.attachmentId,
      contentType: vector.pointer.ct,
      plaintext,
    });
    expect(toHex(blob)).toBe(vector.blob);
    expect(pointer).toEqual(vector.pointer);
    expect(MESSAGES.A2.innerPayloadJson).toContain(JSON.stringify(vector.pointer));
    expect(await decryptAttachment(subtle, pointer, blob)).toEqual(plaintext);

    const tampered = blob.slice();
    tampered[0] ^= 1;
    await expect(decryptAttachment(subtle, pointer, tampered)).rejects.toThrow('digest');
    await expect(decryptAttachment(subtle, { ...pointer, id: 'att-kat-0002' }, blob)).rejects.toThrow('authentication');
  });
});
