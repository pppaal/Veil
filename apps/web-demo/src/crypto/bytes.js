// Byte helpers for the protocol-v2 modules. Integers are big-endian, as in
// docs/crypto-envelope-spec.md §Notation.

const encoder = new TextEncoder();
const strictDecoder = new TextDecoder('utf-8', { fatal: true });

const MAX_U16 = 0xffff;

export const utf8 = (text) => encoder.encode(text);

// Throws on invalid UTF-8: authenticated bytes can still be hostile, and a
// lenient decode would turn them into replacement characters silently.
export const fromUtf8 = (bytes) => strictDecoder.decode(bytes);

// Lowercase hex, the form the API takes digests and shows fingerprints in.
export const toHex = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');

export function concatBytes(parts) {
  let length = 0;
  for (const part of parts) length += part.length;
  const out = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function u16be(value) {
  const out = new Uint8Array(2);
  new DataView(out.buffer).setUint16(0, value);
  return out;
}

export function u32be(value) {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, value);
  return out;
}

// value is a non-negative safe integer (a millisecond timestamp).
export function u64be(value) {
  const out = new Uint8Array(8);
  const view = new DataView(out.buffer);
  view.setUint32(0, Math.floor(value / 2 ** 32));
  view.setUint32(4, value >>> 0);
  return out;
}

export function readU32be(bytes, offset) {
  return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(offset);
}

export const fitsLengthPrefix = (text) => typeof text === 'string' && utf8(text).length <= MAX_U16;

// lp(s) = u16be(len(utf8(s))) || utf8(s)
export function lengthPrefixed(text) {
  const bytes = utf8(text);
  if (bytes.length > MAX_U16) throw new RangeError('field too long to length-prefix');
  return concatBytes([u16be(bytes.length), bytes]);
}

export function constantTimeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

// Bytewise lexicographic order: negative when a sorts first.
export function compareBytes(a, b) {
  const shared = Math.min(a.length, b.length);
  for (let i = 0; i < shared; i += 1) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

export const isAllZero = (bytes) => bytes.every((byte) => byte === 0);

// Overwrites secrets once they are spent. JavaScript gives no guarantee that
// no copy survives, but the buffers we own stop holding them.
export function zeroize(...buffers) {
  for (const buffer of buffers) buffer?.fill(0);
}
