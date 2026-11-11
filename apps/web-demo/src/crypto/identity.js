// Device identity: an Ed25519 key that signs auth challenges and an X25519
// key for the envelope ECDH. Private halves are created non-extractable, so
// script running in the page (an XSS, a hostile extension) can at most use
// them while the page is open, never copy them out. With device-bound
// identity and no recovery, a copied key would be a permanent, silent
// takeover. Public halves stay exportable whatever the flag says.

import { encodeBase64Url } from '../core/base64url.js';

const ED25519 = { name: 'Ed25519' };
const X25519 = { name: 'X25519' };

const PRIVATE_KEY_SLOTS = [
  {
    keyField: 'edPrivKey',
    publicField: 'edPubB64u',
    algorithm: ED25519,
    usages: ['sign'],
    legacyJwkFields: ['edPrivJwk', 'edJwkPriv'],
  },
  {
    keyField: 'xPrivKey',
    publicField: 'xPubB64u',
    algorithm: X25519,
    usages: ['deriveBits'],
    legacyJwkFields: ['xPrivJwk', 'xJwkPriv'],
  },
];

const JWK_FIELD_RE = /jwk/i;

export async function generateIdentity(subtle) {
  const ed = await subtle.generateKey(ED25519, false, ['sign', 'verify']);
  const x = await subtle.generateKey(X25519, false, ['deriveBits']);
  return {
    edPrivKey: ed.privateKey,
    edPubB64u: encodeBase64Url(await subtle.exportKey('raw', ed.publicKey)),
    xPrivKey: x.privateKey,
    xPubB64u: encodeBase64Url(await subtle.exportKey('raw', x.publicKey)),
  };
}

export async function signChallenge(subtle, edPrivKey, challenge) {
  const signature = await subtle.sign(ED25519, edPrivKey, new TextEncoder().encode(challenge));
  return encodeBase64Url(signature);
}

// Brings a stored session record up to the current key hygiene and reports
// whether it changed, so the caller re-saves it. Runs on every restore:
//  - private keys held as JWK by older builds (including the device-transfer
//    path) are imported as non-extractable CryptoKeys;
//  - extractable CryptoKeys from builds that generated them that way are
//    sealed as non-extractable;
//  - every field whose name mentions JWK is deleted.
// An import failure throws before anything is deleted, so the only copy of a
// key is never dropped.
export async function migrateStoredIdentity(record, subtle) {
  const migrated = { ...record };
  let changed = false;
  for (const slot of PRIVATE_KEY_SLOTS) {
    const current = migrated[slot.keyField];
    if (isCryptoKey(current)) {
      if (current.extractable) {
        const sealed = await sealExtractableKey(subtle, current, slot);
        changed ||= sealed !== current;
        migrated[slot.keyField] = sealed;
      }
      continue;
    }
    const jwk = slot.legacyJwkFields.map((field) => migrated[field]).find(isJwk);
    if (!jwk) continue;
    migrated[slot.keyField] = await importNonExtractableJwk(subtle, jwk, slot);
    migrated[slot.publicField] ??= jwk.x;
    changed = true;
  }
  for (const field of Object.keys(migrated)) {
    if (JWK_FIELD_RE.test(field)) {
      delete migrated[field];
      changed = true;
    }
  }
  return { record: migrated, changed };
}

function importNonExtractableJwk(subtle, jwk, slot) {
  // key_ops/ext from the old export would otherwise constrain the import.
  const material = { kty: jwk.kty, crv: jwk.crv, d: jwk.d, x: jwk.x };
  return subtle.importKey('jwk', material, slot.algorithm, false, slot.usages);
}

// The key is already exportable when this runs, so the PKCS#8 round trip
// exposes nothing new and closes the export path for the rest of the key's
// life. If the browser refuses, the existing key is kept: losing the
// identity over a hardening step would be worse than leaving it as it was.
async function sealExtractableKey(subtle, key, slot) {
  try {
    const pkcs8 = await subtle.exportKey('pkcs8', key);
    return await subtle.importKey('pkcs8', pkcs8, slot.algorithm, false, slot.usages);
  } catch {
    return key;
  }
}

function isCryptoKey(value) {
  return typeof CryptoKey !== 'undefined' && value instanceof CryptoKey;
}

function isJwk(value) {
  return value != null && typeof value === 'object' && typeof value.d === 'string';
}
