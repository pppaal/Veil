// X3DH for protocol v2 (docs/crypto-envelope-spec.md §X3DH).
//
//   DH1 = DH(IKx_A, SPK_B)    authenticates A: needs A's IKx private key
//   DH2 = DH(EK, IKx_B)
//   DH3 = DH(EK, SPK_B)
//   DH4 = DH(EK, OPK_B)       only when an OPK was claimed
//   SK  = HKDF(0xFF*32 || DH1 || DH2 || DH3 [|| DH4], salt 0x00*32,
//              info "veil-x3dh-v2" || IKed_A || IKed_B, 32)
//   AD  = IKed_A || IKx_A || IKed_B || IKx_B
//
// A party holding nothing but public bundles (the server included) cannot
// compute DH1, so it cannot open a session as A.

import { concatBytes, readU32be, u32be, utf8, zeroize } from './bytes.js';
import { hkdfSha256 } from './kdf.js';
import { x25519 } from './keys.js';

const X3DH_INFO_LABEL = utf8('veil-x3dh-v2');
const X3DH_PREFIX = new Uint8Array(32).fill(0xff);
const X3DH_SALT = new Uint8Array(32);

export const NO_ONE_TIME_PREKEY_ID = 0xffffffff;
// IKed_A(32) || IKx_A(32) || ikxSig_A(64) || EK(32) || u32be(spkId) || u32be(opkId)
export const PRE_KEY_HEADER_BYTES = 168;

export function encodePreKeyHeader(header) {
  return concatBytes([
    header.identityEd25519,
    header.identityX25519,
    header.identityX25519Signature,
    header.baseKey,
    u32be(header.signedPrekeyId),
    u32be(header.oneTimePrekeyId),
  ]);
}

export function decodePreKeyHeader(bytes, offset = 0) {
  if (bytes.length - offset < PRE_KEY_HEADER_BYTES) throw new RangeError('PreKey header truncated');
  const take = (start, length) => bytes.slice(offset + start, offset + start + length);
  return {
    identityEd25519: take(0, 32),
    identityX25519: take(32, 32),
    identityX25519Signature: take(64, 64),
    // EK_A; also names the session a PreKey frame belongs to.
    baseKey: take(128, 32),
    signedPrekeyId: readU32be(bytes, offset + 160),
    oneTimePrekeyId: readU32be(bytes, offset + 164),
  };
}

export async function deriveInitiatorKeys(subtle, {
  identityEd25519,
  identityX25519Private,
  identityX25519,
  ephemeralPrivate,
  remoteIdentityEd25519,
  remoteIdentityX25519,
  remoteSignedPrekey,
  remoteOneTimePrekey = null,
}) {
  const secrets = await agreeAll(subtle, [
    [identityX25519Private, remoteSignedPrekey],
    [ephemeralPrivate, remoteIdentityX25519],
    [ephemeralPrivate, remoteSignedPrekey],
    ...(remoteOneTimePrekey ? [[ephemeralPrivate, remoteOneTimePrekey]] : []),
  ]);
  return finish(subtle, secrets, {
    initiatorEd25519: identityEd25519,
    initiatorX25519: identityX25519,
    responderEd25519: remoteIdentityEd25519,
    responderX25519: remoteIdentityX25519,
  });
}

export async function deriveResponderKeys(subtle, {
  header,
  identityEd25519,
  identityX25519Private,
  identityX25519,
  signedPrekeyPrivate,
  oneTimePrekeyPrivate = null,
}) {
  const secrets = await agreeAll(subtle, [
    [signedPrekeyPrivate, header.identityX25519],
    [identityX25519Private, header.baseKey],
    [signedPrekeyPrivate, header.baseKey],
    ...(oneTimePrekeyPrivate ? [[oneTimePrekeyPrivate, header.baseKey]] : []),
  ]);
  return finish(subtle, secrets, {
    initiatorEd25519: header.identityEd25519,
    initiatorX25519: header.identityX25519,
    responderEd25519: identityEd25519,
    responderX25519: identityX25519,
  });
}

// A low-order key aborts with KeyAgreementError after wiping what was
// already computed.
async function agreeAll(subtle, pairs) {
  const secrets = [];
  try {
    for (const [privateKey, publicKey] of pairs) secrets.push(await x25519(subtle, privateKey, publicKey));
    return secrets;
  } catch (error) {
    zeroize(...secrets);
    throw error;
  }
}

// The 0xFF prefix is X3DH's domain separator against other uses of the same
// X25519 keys.
async function finish(subtle, secrets, { initiatorEd25519, initiatorX25519, responderEd25519, responderX25519 }) {
  const ikm = concatBytes([X3DH_PREFIX, ...secrets]);
  const sharedKey = await hkdfSha256(subtle, {
    ikm,
    salt: X3DH_SALT,
    info: concatBytes([X3DH_INFO_LABEL, initiatorEd25519, responderEd25519]),
    length: 32,
  });
  zeroize(ikm, ...secrets);
  return {
    sharedKey,
    associatedData: concatBytes([initiatorEd25519, initiatorX25519, responderEd25519, responderX25519]),
  };
}
