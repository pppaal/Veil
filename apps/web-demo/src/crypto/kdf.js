// The ratchet's key derivations (docs/crypto-envelope-spec.md §Double
// Ratchet). Labels and salts are wire format, pinned by
// packages/shared/test-vectors/crypto-kat.json.

import { utf8 } from './bytes.js';

const ROOT_KDF_INFO = utf8('veil-dh-rk-v2');
const MESSAGE_KEY_INFO = utf8('veil-msg-v1');
const CHAIN_KEY_INFO = utf8('veil-chain-next-v1');
const CHAIN_KEY_SALT = Uint8Array.of(0);

export async function hkdfSha256(subtle, { ikm, salt, info, length }) {
  const key = await subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  return new Uint8Array(await subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8));
}

// KDF_RK(rk, dh) -> (rk', ck): one DH ratchet step.
export async function kdfRoot(subtle, rootKey, dhOutput) {
  const out = await hkdfSha256(subtle, { ikm: dhOutput, salt: rootKey, info: ROOT_KDF_INFO, length: 64 });
  const keys = { rootKey: out.slice(0, 32), chainKey: out.slice(32) };
  out.fill(0);
  return keys;
}

export const deriveMessageKey = (subtle, chainKey, counter) =>
  hkdfSha256(subtle, { ikm: chainKey, salt: utf8(`veil-msg-n${counter}`), info: MESSAGE_KEY_INFO, length: 32 });

export const nextChainKey = (subtle, chainKey) =>
  hkdfSha256(subtle, { ikm: chainKey, salt: CHAIN_KEY_SALT, info: CHAIN_KEY_INFO, length: 32 });
