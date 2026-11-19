// Identity keys and the published prekey bundle (contract C1,
// docs/crypto-envelope-spec.md §Identity keys and the bundle).
//
//   identityPublicKey  = b64u(IKed)                 Ed25519
//   ikxSig             = Ed25519(IK, "veil-ikx-v2" || IKx)
//   spkSig             = Ed25519(IK, "veil-spk-v2" || u32be(spkId) || u64be(spkTs) || SPK)
//   signedPrekeyBundle = b64u(compact JSON {v, ikx, ikxSig, spkId, spk, spkTs, spkSig})
//
// The key order of the JSON is fixed so every implementation produces the
// same string.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { concatBytes, fromUtf8, u32be, u64be, utf8 } from './bytes.js';
import { ED25519_SIGNATURE_BYTES, ed25519Sign, ed25519Verify, KEY_BYTES } from './keys.js';

const IKX_SIGNATURE_LABEL = utf8('veil-ikx-v2');
const SPK_SIGNATURE_LABEL = utf8('veil-spk-v2');
const BUNDLE_VERSION = 2;
const MAX_U32 = 0xffffffff;
const DAY_MS = 24 * 60 * 60 * 1000;
// A replayed abandoned prekey would extend its exposure window; a far-future
// stamp would outlive every rotation.
const MAX_SPK_AGE_MS = 60 * DAY_MS;
const MAX_SPK_FUTURE_SKEW_MS = DAY_MS;

export class BundleError extends Error {
  // reason: 'unsupported' (not a v2 bundle: a peer that never upgraded),
  // 'malformed', 'bad_signature', 'stale' or 'future'.
  constructor(reason) {
    super(`prekey bundle rejected: ${reason}`);
    this.name = 'BundleError';
    this.reason = reason;
  }
}

const ikxSignedMessage = (ikx) => concatBytes([IKX_SIGNATURE_LABEL, ikx]);

const spkSignedMessage = (spkId, spkTs, spk) =>
  concatBytes([SPK_SIGNATURE_LABEL, u32be(spkId), u64be(spkTs), spk]);

function encodeBundle({ ikx, ikxSig, spkId, spk, spkTs, spkSig }) {
  const json = JSON.stringify({
    v: BUNDLE_VERSION,
    ikx: encodeBase64Url(ikx),
    ikxSig: encodeBase64Url(ikxSig),
    spkId,
    spk: encodeBase64Url(spk),
    spkTs,
    spkSig: encodeBase64Url(spkSig),
  });
  return encodeBase64Url(utf8(json));
}

// spk: { id, publicKey, createdAt (ms) }
export async function signBundle(subtle, identityPrivateKey, { ikx, ikxSig, spk }) {
  const spkSig = await ed25519Sign(subtle, identityPrivateKey, spkSignedMessage(spk.id, spk.createdAt, spk.publicKey));
  return encodeBundle({ ikx, ikxSig, spkId: spk.id, spk: spk.publicKey, spkTs: spk.createdAt, spkSig });
}

// A fresh protocol-v2 identity: IK, IKx certified by IK, and signed prekey 1.
// Keys are drawn in the order the mobile adapter draws them.
export async function createIdentityKeys(subtle, keys, nowMs) {
  const ik = await keys.ed25519();
  const ikx = await keys.x25519();
  const spkPair = await keys.x25519();
  const ikxSig = await ed25519Sign(subtle, ik.privateKey, ikxSignedMessage(ikx.publicKey));
  const spk = { id: 1, privateKey: spkPair.privateKey, publicKey: spkPair.publicKey, createdAt: nowMs };
  const bundle = await signBundle(subtle, ik.privateKey, { ikx: ikx.publicKey, ikxSig, spk });
  return { ik, ikx, ikxSig, spk, bundle };
}

// Parses and authenticates a directory bundle against the peer's Ed25519
// identity key. A server that swaps any key cannot re-sign it, so every
// failure throws: there is no fallback.
export async function verifyBundle(subtle, encoded, identityKey, { nowMs }) {
  const fields = parseBundle(encoded);
  if (identityKey?.length !== KEY_BYTES) throw new BundleError('malformed');
  const ikxValid = await ed25519Verify(subtle, identityKey, ikxSignedMessage(fields.ikx), fields.ikxSig);
  const spkValid = ikxValid
    && await ed25519Verify(subtle, identityKey, spkSignedMessage(fields.spkId, fields.spkTs, fields.spk), fields.spkSig);
  if (!spkValid) throw new BundleError('bad_signature');
  if (nowMs - fields.spkTs > MAX_SPK_AGE_MS) throw new BundleError('stale');
  if (fields.spkTs - nowMs > MAX_SPK_FUTURE_SKEW_MS) throw new BundleError('future');
  return { ikx: fields.ikx, spkId: fields.spkId, spk: fields.spk, spkTs: fields.spkTs };
}

export async function verifyIkxSignature(subtle, identityKey, ikx, signature) {
  return ed25519Verify(subtle, identityKey, ikxSignedMessage(ikx), signature);
}

function parseBundle(encoded) {
  let map;
  try {
    map = JSON.parse(fromUtf8(decodeBase64Url(encoded)));
  } catch {
    throw new BundleError('unsupported');
  }
  if (map === null || typeof map !== 'object' || map.v !== BUNDLE_VERSION) throw new BundleError('unsupported');
  const { spkId, spkTs } = map;
  if (!Number.isInteger(spkId) || spkId < 0 || spkId > MAX_U32 || !Number.isSafeInteger(spkTs) || spkTs < 0) {
    throw new BundleError('malformed');
  }
  return {
    ikx: bytesField(map.ikx, KEY_BYTES),
    ikxSig: bytesField(map.ikxSig, ED25519_SIGNATURE_BYTES),
    spkId,
    spk: bytesField(map.spk, KEY_BYTES),
    spkTs,
    spkSig: bytesField(map.spkSig, ED25519_SIGNATURE_BYTES),
  };
}

function bytesField(value, length) {
  let bytes;
  try {
    bytes = decodeBase64Url(value);
  } catch {
    throw new BundleError('malformed');
  }
  if (bytes.length !== length) throw new BundleError('malformed');
  return bytes;
}
