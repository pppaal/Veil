// Safety numbers v2 (contract C8, Signal's NumericFingerprint), reproducing
// packages/shared/test-vectors/safety-number-v2.json:
//   per party  h = SHA-512(u16be(version) || IKed || utf8(userId));
//              5200 times h = SHA-512(h || IKed);
//              30 digits = six 5-byte big-endian chunks of h, each mod 100000
//   number     the two halves joined, the lexicographically smaller first
// and the verification code
//   b64u("VEILSN" || u8(version) || localKey || u8(len) || utf8(localUserId)
//        || remoteKey || u8(len) || utf8(remoteUserId))
// which a peer accepts only as the role-swapped code of its own view.
//
// Computed from pinned keys and user ids only; a safety number is never sent
// to the server.

import { encodeBase64Url } from '../core/base64url.js';
import { concatBytes, u16be, utf8 } from './bytes.js';

const SAFETY_NUMBER_VERSION = 2;
const ITERATIONS = 5200;
const CHUNKS = 6;
const CHUNK_BYTES = 5;
const VERIFICATION_MAGIC = utf8('VEILSN');
const MAX_USER_ID_BYTES = 255;

const sha512 = async (subtle, bytes) => new Uint8Array(await subtle.digest('SHA-512', bytes));

export async function fingerprint(subtle, identityKey, userId, version = SAFETY_NUMBER_VERSION) {
  let hash = await sha512(subtle, concatBytes([u16be(version), identityKey, utf8(userId)]));
  for (let i = 0; i < ITERATIONS; i += 1) hash = await sha512(subtle, concatBytes([hash, identityKey]));
  let digits = '';
  for (let chunk = 0; chunk < CHUNKS; chunk += 1) {
    let value = 0;
    for (let i = 0; i < CHUNK_BYTES; i += 1) value = value * 256 + hash[chunk * CHUNK_BYTES + i];
    digits += String(value % 100000).padStart(5, '0');
  }
  return digits;
}

// local, remote: { identityKey (32 bytes), userId }
export async function safetyNumber(subtle, local, remote) {
  const [mine, theirs] = await Promise.all([
    fingerprint(subtle, local.identityKey, local.userId),
    fingerprint(subtle, remote.identityKey, remote.userId),
  ]);
  return mine <= theirs ? mine + theirs : theirs + mine;
}

export const formatSafetyNumber = (digits) => digits.match(/\d{5}/g).join(' ');

export function verificationCode(local, remote) {
  return encodeBase64Url(concatBytes([
    VERIFICATION_MAGIC,
    Uint8Array.of(SAFETY_NUMBER_VERSION),
    local.identityKey,
    lengthPrefixedUserId(local.userId),
    remote.identityKey,
    lengthPrefixedUserId(remote.userId),
  ]));
}

// The code the peer shows is its own view: us as remote, it as local.
export const matchesPeerCode = (local, remote, code) => code === verificationCode(remote, local);

function lengthPrefixedUserId(userId) {
  const bytes = utf8(userId);
  if (bytes.length < 1 || bytes.length > MAX_USER_ID_BYTES) throw new RangeError('userId out of range');
  return concatBytes([Uint8Array.of(bytes.length), bytes]);
}
