// Device identity. A protocol-v2 identity is
//   edPrivKey / edPubB64u   Ed25519 auth key: signs auth challenges and
//                           device-transfer proofs, nothing else
//   ik                      Ed25519 identity key (IKed): signs only IKx and
//                           signed prekeys, so a challenge string the server
//                           picks can never double as a bundle signature
//   ikx, signedPrekeys      X25519 identity key and signed prekeys
//                           (src/crypto/prekeys.js)
//   sessionKek              AES-GCM key sealing the stored ratchet states
// Every private key is created non-extractable, so script running in the
// page (an XSS, a hostile extension) can at most use it while the page is
// open, never copy it out. With device-bound identity and no recovery, a
// copied key would be a permanent, silent takeover. Public halves stay
// exportable whatever the flag says.
//
// Identities from before protocol v2 published their X25519 key as the
// identity key. The directory pins that key for the device's lifetime, so
// such an identity can never publish a v2 bundle: it can still read its old
// history (src/crypto/legacy-v1dev.js) but has to be replaced to send.

import { encodeBase64Url } from '../core/base64url.js';
import { createIdentityKeys, signBundle } from './bundle.js';
import { ED25519, generateEd25519, generateStorageKey, generateX25519, X25519 } from './keys.js';

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

export const isLegacyIdentity = (record) => !record?.ik;

// The identity fields of a new device record.
export async function generateIdentity(subtle, { nowMs = Date.now() } = {}) {
  const auth = await generateEd25519(subtle);
  const keys = { x25519: () => generateX25519(subtle), ed25519: () => generateEd25519(subtle) };
  const { ik, ikx, ikxSig, spk } = await createIdentityKeys(subtle, keys, nowMs);
  return {
    edPrivKey: auth.privateKey,
    edPubB64u: encodeBase64Url(auth.publicKey),
    ik,
    ikx: { ...ikx, signature: ikxSig },
    // Published with the registration (or transfer claim) itself.
    signedPrekeys: [{ ...spk, publishedAt: nowMs, supersededAt: null }],
    nextOneTimePrekeyId: 1,
    sessionKek: await generateStorageKey(subtle),
  };
}

// What /auth/register and /device-transfer/claim publish for an identity:
// its keys and the bundle of its current signed prekey.
export async function publishedKeys(subtle, identity) {
  const current = identity.signedPrekeys.find((spk) => spk.supersededAt === null);
  return {
    publicIdentityKey: encodeBase64Url(identity.ik.publicKey),
    signedPrekeyBundle: await signBundle(subtle, identity.ik.privateKey, {
      ikx: identity.ikx.publicKey,
      ikxSig: identity.ikx.signature,
      spk: current,
    }),
    authPublicKey: identity.edPubB64u,
  };
}

export async function signChallenge(subtle, edPrivKey, challenge) {
  const signature = await subtle.sign(ED25519, edPrivKey, new TextEncoder().encode(challenge));
  return encodeBase64Url(signature);
}

// Brings a stored session record up to the current key hygiene and reports
// whether it changed, so the caller re-saves it. Runs on every restore, and
// concerns the key slots of identities from before protocol v2:
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
