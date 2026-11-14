// One-time secret links (s.html). Fragments are never sent to the server.
//
// v2, the only format sealed here. The fragment always carries a random
// 256-bit key; an optional passphrase is a second factor mixed in through
// PBKDF2, never the only secret: the server holds the ciphertext and salt, so
// a passphrase-only link could be brute-forced offline by whoever runs it.
//
//   blob     = "v2." + b64u(salt16) + "." + b64u(iv12) + "." + b64u(AES-256-GCM ciphertext)
//   fragment = <id> "." ("k2" | "p2") "." b64u(fragmentKey32)       p2 = passphrase required
//   key      = HKDF-SHA256(ikm = fragmentKey || PBKDF2-SHA256(NFC(passphrase), salt, 600000, 32 bytes),
//                          salt, info = "veil-secret-v2")
// Without a passphrase the ikm is the fragment key alone. The passphrase is
// sealed in Unicode NFC, so it opens however the reader's keyboard composes
// the same characters. Links sealed before that used it as typed, as v1 does,
// so opening falls back to the passphrase as typed when NFC changes it.
//
// v1 is read-only. The mobile app still seals it (one_time_link.dart), and
// opening its links exposes nothing new: a key-mode link already carries a
// random key, and a passphrase-only blob already sits on the server. Remove
// this path once mobile seals v2.
//
//   key mode:        blob = "v1." b64u(iv12) "." b64u(ct)                   fragment = <id> ".k." b64u(aesKey32)
//   passphrase mode: blob = "v1." b64u(iv12) "." b64u(ct) "." b64u(salt16)  fragment = <id> ".p"
//                    key  = PBKDF2-SHA256(passphrase, salt, 210000, 32 bytes)
//
// The fragment mode fixes the blob version a link opens, so a blob in another
// format is refused rather than decrypted under a different key schedule.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';

export const PBKDF2_ITERATIONS = 600_000;
const LEGACY_PBKDF2_ITERATIONS = 210_000;
const SEALED_VERSION = 'v2';
const HKDF_INFO = new TextEncoder().encode('veil-secret-v2');
const KEY_BYTES = 32;
const SALT_BYTES = 16;
const IV_BYTES = 12;

const FRAGMENT_MODES = Object.freeze({
  k2: { version: 'v2', carriesKey: true, needsPassphrase: false },
  p2: { version: 'v2', carriesKey: true, needsPassphrase: true },
  k: { version: 'v1', carriesKey: true, needsPassphrase: false },
  p: { version: 'v1', carriesKey: false, needsPassphrase: true },
});

export async function sealSecret(crypto, plaintext, passphrase = '') {
  const fragmentKey = crypto.getRandomValues(new Uint8Array(KEY_BYTES));
  const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
  const key = await deriveSecretKey(crypto.subtle, fragmentKey, salt, passphrase.normalize('NFC'));
  const sealed = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plaintext));
  const mode = passphrase ? 'p2' : 'k2';
  return {
    blob: [SEALED_VERSION, encodeBase64Url(salt), encodeBase64Url(iv), encodeBase64Url(sealed)].join('.'),
    fragmentSecret: `${mode}.${encodeBase64Url(fragmentKey)}`,
  };
}

// `link` is what parseSecretFragment returned for the page's fragment.
export async function openSecret(crypto, blob, link, passphrase = '') {
  const [version, ...fields] = String(blob).split('.');
  if (version !== link.version) throw unsupportedFormat();
  const open = version === SEALED_VERSION ? openVersion2 : openLegacyVersion1;
  const attempt = (candidate) => open(crypto.subtle, fields, link.fragmentKey, candidate);
  const normalized = passphrase.normalize('NFC');
  let opened;
  try {
    opened = await attempt(normalized);
  } catch (error) {
    if (normalized === passphrase) throw error;
    opened = await attempt(passphrase);
  }
  return new TextDecoder().decode(opened);
}

export function formatSecretFragment(id, fragmentSecret) {
  return `${id}.${fragmentSecret}`;
}

// Returns { id, version, needsPassphrase, fragmentKey } or null for a
// malformed link. fragmentKey is null only for a v1 passphrase link.
export function parseSecretFragment(fragment) {
  const [id, mode, ...keyField] = String(fragment).split('.');
  const format = Object.hasOwn(FRAGMENT_MODES, mode) ? FRAGMENT_MODES[mode] : null;
  if (!id || !format || keyField.length !== (format.carriesKey ? 1 : 0)) return null;
  const fragmentKey = format.carriesKey ? decodeFragmentKey(keyField[0]) : null;
  if (format.carriesKey && fragmentKey === null) return null;
  return { id, version: format.version, needsPassphrase: format.needsPassphrase, fragmentKey };
}

function decodeFragmentKey(encoded) {
  try {
    const key = decodeBase64Url(encoded);
    return key.length === KEY_BYTES ? key : null;
  } catch {
    return null;
  }
}

async function openVersion2(subtle, fields, fragmentKey, passphrase) {
  if (fields.length !== 3) throw unsupportedFormat();
  const [salt, iv, sealed] = fields.map(decodeBase64Url);
  const key = await deriveSecretKey(subtle, fragmentKey, salt, passphrase);
  return subtle.decrypt({ name: 'AES-GCM', iv }, key, sealed);
}

async function openLegacyVersion1(subtle, fields, fragmentKey, passphrase) {
  // A key-mode blob has no salt; a passphrase-mode blob appends one.
  if (fields.length !== (fragmentKey ? 2 : 3)) throw unsupportedFormat();
  const [iv, sealed, salt] = fields.map(decodeBase64Url);
  const rawKey = fragmentKey ?? await stretchPassphrase(subtle, passphrase, salt, LEGACY_PBKDF2_ITERATIONS);
  const key = await subtle.importKey('raw', rawKey, 'AES-GCM', false, ['decrypt']);
  return subtle.decrypt({ name: 'AES-GCM', iv }, key, sealed);
}

async function deriveSecretKey(subtle, fragmentKey, salt, passphrase) {
  let ikm = fragmentKey;
  if (passphrase) {
    const stretched = await stretchPassphrase(subtle, passphrase, salt, PBKDF2_ITERATIONS);
    ikm = new Uint8Array(fragmentKey.length + stretched.length);
    ikm.set(fragmentKey);
    ikm.set(stretched, fragmentKey.length);
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

async function stretchPassphrase(subtle, passphrase, salt, iterations) {
  const base = await subtle.importKey('raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveBits']);
  const bits = await subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, base, KEY_BYTES * 8);
  return new Uint8Array(bits);
}

function unsupportedFormat() {
  return new Error('unsupported secret format');
}
