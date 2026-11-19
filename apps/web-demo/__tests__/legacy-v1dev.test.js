// The retired 'veil-envelope-v1-dev' format is read-only: history earlier
// builds wrote still decrypts, and nothing can produce it any more.

import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';

import { buildAad } from '../lib/aad.js';
import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { createLegacyV1DevReader, isLegacyV1DevEnvelope } from '../src/crypto/legacy-v1dev.js';

const { subtle } = webcrypto;
const CONVERSATION = '6f0c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5b';

// A pre-v2 identity as earlier builds stored it: X25519 (and Ed25519 auth)
// keys, non-extractable.
async function legacyIdentity() {
  const x = await subtle.generateKey({ name: 'X25519' }, false, ['deriveBits']);
  return { xPrivKey: x.privateKey, xPubB64u: encodeBase64Url(await subtle.exportKey('raw', x.publicKey)) };
}

// Independent re-statement of the original app.js envelope code
// (getConvCryptoCtx / encryptForConv), so the reader is checked against the
// wire format rather than against itself.
async function originalContext(self, peerXPubB64u) {
  const peer = await subtle.importKey('raw', decodeBase64Url(peerXPubB64u), { name: 'X25519' }, false, []);
  const bits = await subtle.deriveBits({ name: 'X25519', public: peer }, self.xPrivKey, 256);
  const hkdfBase = await subtle.importKey('raw', bits, 'HKDF', false, ['deriveKey']);
  const sorted = [self.xPubB64u, peerXPubB64u].sort().join('|');
  return { hkdfBase, info: new TextEncoder().encode(`veil-demo-v2|aesgcm|${sorted}|${CONVERSATION}`) };
}

async function originalEncrypt(ctx, senderDeviceId, plaintext, { withAad = true } = {}) {
  const nonce = webcrypto.getRandomValues(new Uint8Array(12));
  const key = await subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: nonce, info: ctx.info }, ctx.hkdfBase,
    { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
  const params = withAad
    ? { name: 'AES-GCM', iv: nonce, additionalData: buildAad({ conversationId: CONVERSATION, senderDeviceId }) }
    : { name: 'AES-GCM', iv: nonce };
  const ct = await subtle.encrypt(params, key, new TextEncoder().encode(plaintext));
  return { ciphertext: 'v2.' + encodeBase64Url(ct), nonce: encodeBase64Url(nonce) };
}

async function setup() {
  const alice = await legacyIdentity();
  const bob = await legacyIdentity();
  const aliceReader = createLegacyV1DevReader({
    subtle,
    getSelf: () => alice,
    peerKey: async (conversationId) => (conversationId === CONVERSATION ? bob.xPubB64u : null),
  });
  return { aliceReader, bobContext: await originalContext(bob, alice.xPubB64u) };
}

describe("'veil-envelope-v1-dev' (read-only)", () => {
  it('decrypts what the original client sent, with and without the AAD binding', async () => {
    const { aliceReader, bobContext } = await setup();
    const bound = await originalEncrypt(bobContext, 'd-bob', 'bound');
    const legacy = await originalEncrypt(bobContext, 'd-bob', 'pre-aad', { withAad: false });
    expect(await aliceReader.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...bound })).toEqual({ payload: 'bound' });
    expect(await aliceReader.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...legacy })).toEqual({ payload: 'pre-aad' });
  });

  it('rejects a ciphertext attributed to another device', async () => {
    const { aliceReader, bobContext } = await setup();
    const bound = await originalEncrypt(bobContext, 'd-bob', 'bound');
    expect(await aliceReader.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-mallory', ...bound }))
      .toEqual({ failure: 'failed' });
  });

  it('reports legacy formats and conversations without a pinned peer key', async () => {
    const { aliceReader } = await setup();
    expect(await aliceReader.decrypt({ conversationId: CONVERSATION, ciphertext: 'v1.abc', nonce: 'x' })).toEqual({ failure: 'legacy' });
    expect(await aliceReader.decrypt({ conversationId: 'c-unknown', ciphertext: 'v2.AAAA', nonce: 'AAAA' })).toEqual({ failure: 'no-key' });
    // A protocol-v2 identity holds no X25519 key of the old kind.
    const v2Reader = createLegacyV1DevReader({ subtle, getSelf: () => ({ ik: {} }), peerKey: async () => 'unused' });
    expect(await v2Reader.decrypt({ conversationId: CONVERSATION, ciphertext: 'v2.AAAA', nonce: 'AAAA' })).toEqual({ failure: 'no-key' });
  });

  it('only the retired version is routed here', () => {
    expect(isLegacyV1DevEnvelope({ version: 'veil-envelope-v1-dev' })).toBe(true);
    for (const version of ['veil-envelope-v2', 'veil-envelope-v1', undefined]) {
      expect(isLegacyV1DevEnvelope({ version })).toBe(false);
    }
  });
});
