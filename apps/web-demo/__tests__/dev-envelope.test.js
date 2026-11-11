import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';

import { buildAad } from '../lib/aad.js';
import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { generateIdentity } from '../src/crypto/identity.js';
import { createDevEnvelopeCrypto } from '../src/crypto/dev-envelope.js';

const { subtle } = webcrypto;
const CONVERSATION = '6f0c1a2b-3d4e-4f50-8a9b-0c1d2e3f4a5b';

// Independent re-statement of the original app.js v2 envelope code
// (getConvCryptoCtx / encryptForConv / decryptFromConv), so the module is
// checked against the wire format rather than against itself.
async function originalContext(self, peerXPubB64u) {
  const peer = await subtle.importKey('raw', decodeBase64Url(peerXPubB64u), { name: 'X25519' }, false, []);
  const bits = await subtle.deriveBits({ name: 'X25519', public: peer }, self.xPrivKey, 256);
  const hkdfBase = await subtle.importKey('raw', bits, 'HKDF', false, ['deriveKey']);
  const sorted = [self.xPubB64u, peerXPubB64u].sort().join('|');
  return { hkdfBase, info: new TextEncoder().encode(`veil-demo-v2|aesgcm|${sorted}|${CONVERSATION}`) };
}

function originalKey(ctx, nonce) {
  return subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt: nonce, info: ctx.info }, ctx.hkdfBase,
    { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

async function originalEncrypt(ctx, senderDeviceId, plaintext, { withAad = true } = {}) {
  const nonce = webcrypto.getRandomValues(new Uint8Array(12));
  const params = withAad
    ? { name: 'AES-GCM', iv: nonce, additionalData: buildAad({ conversationId: CONVERSATION, senderDeviceId }) }
    : { name: 'AES-GCM', iv: nonce };
  const ct = await subtle.encrypt(params, await originalKey(ctx, nonce), new TextEncoder().encode(plaintext));
  return { ciphertext: 'v2.' + encodeBase64Url(ct), nonce: encodeBase64Url(nonce) };
}

async function originalDecrypt(ctx, senderDeviceId, { ciphertext, nonce }) {
  const iv = decodeBase64Url(nonce);
  const aad = buildAad({ conversationId: CONVERSATION, senderDeviceId });
  const pt = await subtle.decrypt({ name: 'AES-GCM', iv, additionalData: aad }, await originalKey(ctx, iv), decodeBase64Url(ciphertext.slice(3)));
  return new TextDecoder().decode(pt);
}

function bobDirectory(bob) {
  return {
    resolve: async () => ({ trustedKey: bob.xPubB64u, pendingKey: null }),
    pendingChange: () => null,
  };
}

async function setup() {
  const alice = { userId: 'u-alice', deviceId: 'd-alice', ...(await generateIdentity(subtle)) };
  const bob = { userId: 'u-bob', deviceId: 'd-bob', ...(await generateIdentity(subtle)) };
  const aliceCrypto = createDevEnvelopeCrypto({
    crypto: webcrypto,
    directory: bobDirectory(bob),
    getSelf: () => alice,
    getPeer: () => ({ userId: 'u-bob', handle: 'bob' }),
  });
  return { alice, bob, aliceCrypto, bobContext: await originalContext(bob, alice.xPubB64u) };
}

describe("'veil-envelope-v1-dev' wire crypto", () => {
  it('encrypts exactly as the original client, which can decrypt it', async () => {
    const { aliceCrypto, bobContext } = await setup();
    const sealed = await aliceCrypto.encrypt(CONVERSATION, 'hello bob');
    expect(sealed.ciphertext.startsWith('v2.')).toBe(true);
    expect(decodeBase64Url(sealed.nonce)).toHaveLength(12);
    expect(await originalDecrypt(bobContext, 'd-alice', sealed)).toBe('hello bob');
  });

  it('addresses the envelope to the user whose key sealed it', async () => {
    const { aliceCrypto } = await setup();
    expect((await aliceCrypto.encrypt(CONVERSATION, 'hi')).recipientUserId).toBe('u-bob');
  });

  it('seals nothing until it knows which member is self', async () => {
    const { alice, bob } = await setup();
    const unnamed = { ...alice, userId: null };
    const sealer = (self, peer) => createDevEnvelopeCrypto({
      crypto: webcrypto,
      directory: bobDirectory(bob),
      getSelf: () => self,
      getPeer: () => peer,
    });
    // A device whose login never recorded its userId, in a conversation
    // whose member list starts with itself.
    expect(await sealer(unnamed, { userId: 'u-alice', handle: 'alice' }).encrypt(CONVERSATION, 'x')).toBeNull();
    expect(await sealer(unnamed, { userId: 'u-bob', handle: 'bob' }).encrypt(CONVERSATION, 'x')).toBeNull();
    expect(await sealer(alice, { userId: 'u-alice', handle: 'alice' }).encrypt(CONVERSATION, 'x')).toBeNull();
  });

  it('decrypts what the original client sent, with and without the AAD binding', async () => {
    const { aliceCrypto, bobContext } = await setup();
    const bound = await originalEncrypt(bobContext, 'd-bob', 'bound');
    const legacy = await originalEncrypt(bobContext, 'd-bob', 'pre-aad', { withAad: false });
    expect(await aliceCrypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...bound })).toEqual({ payload: 'bound' });
    expect(await aliceCrypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-bob', ...legacy })).toEqual({ payload: 'pre-aad' });
  });

  it('rejects a ciphertext attributed to another device', async () => {
    const { aliceCrypto, bobContext } = await setup();
    const bound = await originalEncrypt(bobContext, 'd-bob', 'bound');
    expect(await aliceCrypto.decrypt({ conversationId: CONVERSATION, senderDeviceId: 'd-mallory', ...bound }))
      .toEqual({ failure: 'failed' });
  });

  it('reports legacy formats and unknown conversations', async () => {
    const { aliceCrypto } = await setup();
    expect(await aliceCrypto.decrypt({ conversationId: CONVERSATION, ciphertext: 'v1.abc', nonce: 'x' })).toEqual({ failure: 'legacy' });
    const noPeer = createDevEnvelopeCrypto({
      crypto: webcrypto,
      directory: { resolve: async () => { throw new Error('unused'); }, pendingChange: () => null },
      getSelf: () => null,
      getPeer: () => null,
    });
    expect(await noPeer.decrypt({ conversationId: CONVERSATION, ciphertext: 'v2.AAAA', nonce: 'AAAA' })).toEqual({ failure: 'no-key' });
    expect(await noPeer.encrypt(CONVERSATION, 'x')).toBeNull();
  });
});
