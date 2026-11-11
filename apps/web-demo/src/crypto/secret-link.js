// One-time secret links (s.html). The link fragment always carries a random
// 256-bit key, and fragments are never sent to the server. An optional
// passphrase is a second factor mixed in through PBKDF2, never the only
// secret: the server holds the ciphertext and salt, so a passphrase-only
// link could be brute-forced offline by whoever runs it.
//
//   blob     = "v2." + b64u(salt16) + "." + b64u(iv12) + "." + b64u(AES-256-GCM ciphertext)
//   fragment = <id> "." ("k2" | "p2") "." b64u(fragmentKey32)       p2 = passphrase required
//   key      = HKDF-SHA256(ikm = fragmentKey || PBKDF2-SHA256(passphrase, salt, 600000, 32 bytes),
//                          salt, info = "veil-secret-v2")
// Without a passphrase the ikm is the fragment key alone.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';

export const PBKDF2_ITERATIONS = 600_000;
const BLOB_VERSION = 'v2';
const MODE_KEY_ONLY = 'k2';
const MODE_WITH_PASSPHRASE = 'p2';
const HKDF_INFO = new TextEncoder().encode('veil-secret-v2');
const FRAGMENT_KEY_BYTES = 32;
const SALT_BYTES = 16;
const IV_BYTES = 12;

export async function sealSecret(crypto, plaintext, passphrase = '') {
  const fragmentKey = crypto.getRandomValues(new Uint8Array(FRAGMENT_KEY_BYTES));
  const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const key = await deriveSecretKey(crypto.subtle, fragmentKey, salt, passphrase);
  const sealed = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plaintext));
  const mode = passphrase ? MODE_WITH_PASSPHRASE : MODE_KEY_ONLY;
  return {
    blob: [BLOB_VERSION, encodeBase64Url(salt), encodeBase64Url(iv), encodeBase64Url(sealed)].join('.'),
    fragmentSecret: `${mode}.${encodeBase64Url(fragmentKey)}`,
  };
}

export async function openSecret(crypto, blob, { fragmentKey, passphrase = '' }) {
  const [version, salt, iv, sealed] = String(blob).split('.');
  if (version !== BLOB_VERSION || sealed === undefined) throw new Error('unsupported secret format');
  const saltBytes = decodeBase64Url(salt);
  const key = await deriveSecretKey(crypto.subtle, fragmentKey, saltBytes, passphrase);
  const opened = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: decodeBase64Url(iv) }, key, decodeBase64Url(sealed));
  return new TextDecoder().decode(opened);
}

export function formatSecretFragment(id, fragmentSecret) {
  return `${id}.${fragmentSecret}`;
}

// Returns { id, needsPassphrase, fragmentKey } or null for a malformed link.
export function parseSecretFragment(fragment) {
  const [id, mode, encodedKey, ...rest] = String(fragment).split('.');
  if (!id || rest.length > 0 || (mode !== MODE_KEY_ONLY && mode !== MODE_WITH_PASSPHRASE)) return null;
  let fragmentKey;
  try {
    fragmentKey = decodeBase64Url(encodedKey ?? '');
  } catch {
    return null;
  }
  if (fragmentKey.length !== FRAGMENT_KEY_BYTES) return null;
  return { id, needsPassphrase: mode === MODE_WITH_PASSPHRASE, fragmentKey };
}

async function deriveSecretKey(subtle, fragmentKey, salt, passphrase) {
  let ikm = fragmentKey;
  if (passphrase) {
    const base = await subtle.importKey('raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveBits']);
    const stretched = await subtle.deriveBits(
      { name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
      base,
      256,
    );
    ikm = new Uint8Array(fragmentKey.length + stretched.byteLength);
    ikm.set(fragmentKey);
    ikm.set(new Uint8Array(stretched), fragmentKey.length);
  }
  const hkdfKey = await subtle.importKey('raw', ikm, 'HKDF', false, ['deriveKey']);
  return subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt, info: HKDF_INFO },
    hkdfKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}
