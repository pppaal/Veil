import { createPublicKey, verify, type KeyObject } from 'node:crypto';

import { ED25519_SPKI_PREFIX } from '../auth/device-auth-verifier';

/**
 * Signed-prekey bundle v2 (contract C1, shared with the mobile and web
 * clients): base64url-nopad of compact UTF-8 JSON with the keys in exactly
 * this order. Byte fields are base64url-nopad.
 */
const FIELD_ORDER = ['v', 'ikx', 'ikxSig', 'spkId', 'spk', 'spkTs', 'spkSig'] as const;

const IKX_SIGNATURE_CONTEXT = Buffer.from('veil-ikx-v2', 'ascii');
const SPK_SIGNATURE_CONTEXT = Buffer.from('veil-spk-v2', 'ascii');

const X25519_PUBLIC_KEY_BYTES = 32;
const ED25519_PUBLIC_KEY_BYTES = 32;
const ED25519_SIGNATURE_BYTES = 64;
const MAX_U32 = 0xffffffff;

const BASE64URL_ALPHABET = /^[A-Za-z0-9_-]*$/;

export interface SignedPrekeyBundleV2 {
  ikx: Buffer;
  ikxSig: Buffer;
  spkId: number;
  spk: Buffer;
  spkTs: number;
  spkSig: Buffer;
}

/**
 * Strictly decodes a v2 bundle, or returns null for anything else (including
 * legacy v1 bundles). Decoding is canonical end to end — exact key order,
 * compact JSON, no padding or stray base64 bits — so a bundle has exactly one
 * accepted encoding and flipping any byte of it is rejected.
 */
export function decodeSignedPrekeyBundleV2(encoded: string): SignedPrekeyBundleV2 | null {
  const outer = decodeCanonicalBase64Url(encoded);
  if (!outer) {
    return null;
  }

  let json: string;
  let parsed: unknown;
  try {
    json = new TextDecoder('utf-8', { fatal: true }).decode(outer);
    parsed = JSON.parse(json);
  } catch {
    return null;
  }

  if (!isRecord(parsed) || !hasExactKeyOrder(parsed) || JSON.stringify(parsed) !== json) {
    return null;
  }

  const { v, ikx, ikxSig, spkId, spk, spkTs, spkSig } = parsed;
  if (v !== 2 || !isU32(spkId) || !isTimestamp(spkTs)) {
    return null;
  }

  const fields = {
    ikx: decodeField(ikx, X25519_PUBLIC_KEY_BYTES),
    ikxSig: decodeField(ikxSig, ED25519_SIGNATURE_BYTES),
    spk: decodeField(spk, X25519_PUBLIC_KEY_BYTES),
    spkSig: decodeField(spkSig, ED25519_SIGNATURE_BYTES),
  };
  if (!fields.ikx || !fields.ikxSig || !fields.spk || !fields.spkSig) {
    return null;
  }

  return {
    ikx: fields.ikx,
    ikxSig: fields.ikxSig,
    spkId,
    spk: fields.spk,
    spkTs,
    spkSig: fields.spkSig,
  };
}

/**
 * Checks both signatures against the device's raw Ed25519 identity key:
 *   ikxSig = Ed25519(IK, 'veil-ikx-v2' || ikx)
 *   spkSig = Ed25519(IK, 'veil-spk-v2' || u32be(spkId) || u64be(spkTs) || spk)
 */
export function verifySignedPrekeyBundleV2(
  bundle: SignedPrekeyBundleV2,
  identityPublicKey: string,
): boolean {
  const identityKey = importEd25519PublicKey(identityPublicKey);
  if (!identityKey) {
    return false;
  }

  const spkHeader = Buffer.alloc(12);
  spkHeader.writeUInt32BE(bundle.spkId, 0);
  spkHeader.writeBigUInt64BE(BigInt(bundle.spkTs), 4);

  return (
    verify(null, Buffer.concat([IKX_SIGNATURE_CONTEXT, bundle.ikx]), identityKey, bundle.ikxSig) &&
    verify(
      null,
      Buffer.concat([SPK_SIGNATURE_CONTEXT, spkHeader, bundle.spk]),
      identityKey,
      bundle.spkSig,
    )
  );
}

function importEd25519PublicKey(identityPublicKey: string): KeyObject | null {
  const raw = Buffer.from(identityPublicKey, 'base64url');
  if (raw.length !== ED25519_PUBLIC_KEY_BYTES) {
    return null;
  }
  try {
    return createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
      format: 'der',
      type: 'spki',
    });
  } catch {
    return null;
  }
}

function decodeCanonicalBase64Url(value: string): Buffer | null {
  if (!BASE64URL_ALPHABET.test(value)) {
    return null;
  }
  const bytes = Buffer.from(value, 'base64url');
  // Node's decoder ignores trailing bits; re-encoding rejects every alias.
  return bytes.toString('base64url') === value ? bytes : null;
}

function decodeField(value: unknown, expectedBytes: number): Buffer | null {
  if (typeof value !== 'string') {
    return null;
  }
  const bytes = decodeCanonicalBase64Url(value);
  return bytes?.length === expectedBytes ? bytes : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hasExactKeyOrder(value: Record<string, unknown>): boolean {
  const keys = Object.keys(value);
  return (
    keys.length === FIELD_ORDER.length && FIELD_ORDER.every((key, index) => keys[index] === key)
  );
}

function isU32(value: unknown): value is number {
  return Number.isInteger(value) && (value as number) >= 0 && (value as number) <= MAX_U32;
}

function isTimestamp(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}
