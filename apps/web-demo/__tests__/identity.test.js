import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { generateIdentity, migrateStoredIdentity, signChallenge } from '../src/crypto/identity.js';

const { subtle } = webcrypto;

async function verifies(edPubB64u, message, signatureB64u) {
  const publicKey = await subtle.importKey('raw', decodeBase64Url(edPubB64u), { name: 'Ed25519' }, false, ['verify']);
  return subtle.verify({ name: 'Ed25519' }, publicKey, decodeBase64Url(signatureB64u), new TextEncoder().encode(message));
}

async function sharedSecret(privateKey, peerPubB64u) {
  const peer = await subtle.importKey('raw', decodeBase64Url(peerPubB64u), { name: 'X25519' }, false, []);
  return new Uint8Array(await subtle.deriveBits({ name: 'X25519', public: peer }, privateKey, 256));
}

// Session records as earlier builds wrote them: extractable keys, plus the
// JWK copies the device-transfer path and the first IndexedDB builds left.
async function legacyRecord() {
  const ed = await subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const x = await subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
  return {
    ed,
    x,
    edPubB64u: encodeBase64Url(await subtle.exportKey('raw', ed.publicKey)),
    xPubB64u: encodeBase64Url(await subtle.exportKey('raw', x.publicKey)),
    edJwk: await subtle.exportKey('jwk', ed.privateKey),
    xJwk: await subtle.exportKey('jwk', x.privateKey),
  };
}

describe('generateIdentity', () => {
  it('private keys non-extractable and exportKey rejects', async () => {
    const identity = await generateIdentity(subtle);
    for (const key of [identity.edPrivKey, identity.xPrivKey]) {
      expect(key.type).toBe('private');
      expect(key.extractable).toBe(false);
      await expect(subtle.exportKey('jwk', key)).rejects.toThrow();
      await expect(subtle.exportKey('pkcs8', key)).rejects.toThrow();
    }
  });

  it('public raw export works', async () => {
    const alice = await generateIdentity(subtle);
    const bob = await generateIdentity(subtle);
    expect(decodeBase64Url(alice.edPubB64u)).toHaveLength(32);
    expect(decodeBase64Url(alice.xPubB64u)).toHaveLength(32);

    const signature = await signChallenge(subtle, alice.edPrivKey, 'challenge-123');
    expect(await verifies(alice.edPubB64u, 'challenge-123', signature)).toBe(true);
    expect(await verifies(bob.edPubB64u, 'challenge-123', signature)).toBe(false);

    expect(await sharedSecret(alice.xPrivKey, bob.xPubB64u)).toEqual(await sharedSecret(bob.xPrivKey, alice.xPubB64u));
  });
});

describe('migrateStoredIdentity', () => {
  it('migration strips all *Jwk* fields and keeps public keys', async () => {
    const legacy = await legacyRecord();
    // Shape left by the old transfer path (edPrivJwk/xPrivJwk next to the
    // CryptoKeys) and by the first IndexedDB builds (edJwkPriv/xJwkPriv only).
    const fromTransfer = {
      handle: 'alice',
      deviceId: 'device-1',
      edPrivKey: legacy.ed.privateKey,
      xPrivKey: legacy.x.privateKey,
      edPubB64u: legacy.edPubB64u,
      xPubB64u: legacy.xPubB64u,
      edPrivJwk: legacy.edJwk,
      xPrivJwk: legacy.xJwk,
    };
    const jwkOnly = { handle: 'alice', deviceId: 'device-1', edJwkPriv: legacy.edJwk, xJwkPriv: legacy.xJwk };

    for (const stored of [fromTransfer, jwkOnly]) {
      const { record, changed } = await migrateStoredIdentity(stored, subtle);
      expect(changed).toBe(true);
      expect(Object.keys(record).filter((field) => /jwk/i.test(field))).toEqual([]);
      expect(record.edPubB64u).toBe(legacy.edPubB64u);
      expect(record.xPubB64u).toBe(legacy.xPubB64u);
      expect(record.edPrivKey.extractable).toBe(false);
      expect(record.xPrivKey.extractable).toBe(false);
      await expect(subtle.exportKey('pkcs8', record.edPrivKey)).rejects.toThrow();

      const signature = await signChallenge(subtle, record.edPrivKey, 'restore');
      expect(await verifies(legacy.edPubB64u, 'restore', signature)).toBe(true);
      expect(await sharedSecret(record.xPrivKey, legacy.xPubB64u))
        .toEqual(await sharedSecret(legacy.x.privateKey, legacy.xPubB64u));
    }
  });

  it('seals extractable CryptoKeys from older builds', async () => {
    const legacy = await legacyRecord();
    const { record, changed } = await migrateStoredIdentity({
      edPrivKey: legacy.ed.privateKey,
      xPrivKey: legacy.x.privateKey,
      edPubB64u: legacy.edPubB64u,
      xPubB64u: legacy.xPubB64u,
    }, subtle);
    expect(changed).toBe(true);
    expect(record.edPrivKey.extractable).toBe(false);
    expect(record.xPrivKey.extractable).toBe(false);
  });

  it('leaves a current record unchanged and never mutates its input', async () => {
    const identity = await generateIdentity(subtle);
    const stored = { handle: 'bob', deviceId: 'device-2', ...identity };
    const { record, changed } = await migrateStoredIdentity(stored, subtle);
    expect(changed).toBe(false);
    expect(record).toEqual(stored);

    const legacy = await legacyRecord();
    const withJwk = { edJwkPriv: legacy.edJwk, xJwkPriv: legacy.xJwk };
    await migrateStoredIdentity(withJwk, subtle);
    expect(Object.keys(withJwk)).toEqual(['edJwkPriv', 'xJwkPriv']);
  });

  it('keeps the JWK when it cannot be imported', async () => {
    const broken = { edJwkPriv: { kty: 'OKP', crv: 'Ed25519', d: 'not-a-key', x: 'nope' } };
    await expect(migrateStoredIdentity(broken, subtle)).rejects.toThrow();
    expect(broken.edJwkPriv.d).toBe('not-a-key');
  });
});
