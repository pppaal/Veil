// The vetted primitives protocol v2 composes, all from WebCrypto: X25519,
// Ed25519, AES-256-GCM and SHA-256. Every private key is created
// non-extractable, so script running in the page can use a key while the
// page is open but never copy it out.
//
// Randomness is injected through a key source so the known-answer tests can
// replay the reference draws; createKeySource is the production one.

import { isAllZero } from './bytes.js';

export const X25519 = Object.freeze({ name: 'X25519' });
export const ED25519 = Object.freeze({ name: 'Ed25519' });
const AES_GCM = 'AES-GCM';
export const KEY_BYTES = 32;
export const GCM_NONCE_BYTES = 12;
export const GCM_TAG_BYTES = 16;
export const ED25519_SIGNATURE_BYTES = 64;

export class KeyAgreementError extends Error {
  constructor() {
    super('X25519 agreement rejected (low-order or malformed public key)');
    this.name = 'KeyAgreementError';
  }
}

export async function generateX25519(subtle) {
  const pair = await subtle.generateKey(X25519, false, ['deriveBits']);
  return { privateKey: pair.privateKey, publicKey: new Uint8Array(await subtle.exportKey('raw', pair.publicKey)) };
}

export async function generateEd25519(subtle) {
  const pair = await subtle.generateKey(ED25519, false, ['sign', 'verify']);
  return { privateKey: pair.privateKey, publicKey: new Uint8Array(await subtle.exportKey('raw', pair.publicKey)) };
}

// { x25519(), ed25519() } resolve to { privateKey: non-extractable CryptoKey,
// publicKey: raw 32 bytes }; randomBytes(n) draws nonces and attachment keys.
export function createKeySource(crypto) {
  return {
    x25519: () => generateX25519(crypto.subtle),
    ed25519: () => generateEd25519(crypto.subtle),
    randomBytes: (length) => crypto.getRandomValues(new Uint8Array(length)),
  };
}

// DH(priv, pub). An all-zero output means a low-order public key, which the
// spec requires rejecting; browsers that do not refuse it themselves are
// caught here.
export async function x25519(subtle, privateKey, publicKey) {
  if (!(publicKey instanceof Uint8Array) || publicKey.length !== KEY_BYTES) throw new KeyAgreementError();
  let shared;
  try {
    const peer = await subtle.importKey('raw', publicKey, X25519, false, []);
    shared = new Uint8Array(await subtle.deriveBits({ name: 'X25519', public: peer }, privateKey, 256));
  } catch {
    throw new KeyAgreementError();
  }
  if (isAllZero(shared)) throw new KeyAgreementError();
  return shared;
}

export async function ed25519Sign(subtle, privateKey, message) {
  return new Uint8Array(await subtle.sign(ED25519, privateKey, message));
}

export async function ed25519Verify(subtle, publicKey, message, signature) {
  if (publicKey?.length !== KEY_BYTES || signature?.length !== ED25519_SIGNATURE_BYTES) return false;
  try {
    const key = await subtle.importKey('raw', publicKey, ED25519, false, ['verify']);
    return await subtle.verify(ED25519, key, signature, message);
  } catch {
    return false;
  }
}

export async function sha256(subtle, bytes) {
  return new Uint8Array(await subtle.digest('SHA-256', bytes));
}

// One-shot AES-256-GCM under raw key bytes; the result is ciphertext || tag.
export async function aesGcmSeal(subtle, keyBytes, nonce, plaintext, additionalData) {
  const key = await subtle.importKey('raw', keyBytes, AES_GCM, false, ['encrypt']);
  return new Uint8Array(await subtle.encrypt(gcmParams(nonce, additionalData), key, plaintext));
}

// Rejects (OperationError) when the tag does not verify.
export async function aesGcmOpen(subtle, keyBytes, nonce, sealed, additionalData) {
  const key = await subtle.importKey('raw', keyBytes, AES_GCM, false, ['decrypt']);
  return new Uint8Array(await subtle.decrypt(gcmParams(nonce, additionalData), key, sealed));
}

// A storage key: AES-GCM, non-extractable, usable only to seal and open.
export function generateStorageKey(subtle) {
  return subtle.generateKey({ name: AES_GCM, length: 256 }, false, ['encrypt', 'decrypt']);
}

export function gcmParams(nonce, additionalData) {
  return additionalData ? { name: AES_GCM, iv: nonce, additionalData } : { name: AES_GCM, iv: nonce };
}
