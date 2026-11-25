// The authenticated plaintext inside every protocol-v2 frame, byte for byte
// the mobile reference (payload/inner_payload.dart):
//
//   {"pv":2,"b":<body>,"k":<kind>,"x":<expiresAt ms|null>,"att":null|{id,ck,n,d,ct,sz,alg}}
//
// Compact JSON, all five keys always present, in this order. One optional
// key may follow them: "r", the id of the message a reply answers. Peers
// that do not know it ignore it, which the spec's version policy allows for
// additions, and it keeps the reply link out of the server's view. Mobile is
// such a peer today: a web reply reads there as plain text.
// Receivers also accept the legacy {"body","kind","expiresAt","att"} shape.

import { fromUtf8, utf8 } from './bytes.js';

const INNER_PAYLOAD_VERSION = 2;
// The MessageKind names both clients share.
const MESSAGE_KINDS = Object.freeze(['text', 'image', 'file', 'system', 'voice', 'sticker', 'reaction', 'call']);
// Beyond this an instant is not representable (ECMAScript time range).
const MAX_EPOCH_MS = 8.64e15;

export class PayloadFormatError extends Error {
  constructor(message) {
    super(message);
    this.name = 'PayloadFormatError';
  }
}

// attachment: { id, ck, n, d, ct, sz, alg } with byte fields as b64u.
export function encodeInnerPayload({ body, kind, expiresAt = null, attachment = null, replyTo = null }) {
  if (!MESSAGE_KINDS.includes(kind)) throw new TypeError(`unknown message kind: ${kind}`);
  const payload = {
    pv: INNER_PAYLOAD_VERSION,
    b: body,
    k: kind,
    x: expiresAt,
    att: attachment && {
      id: attachment.id,
      ck: attachment.ck,
      n: attachment.n,
      d: attachment.d,
      ct: attachment.ct,
      sz: attachment.sz,
      alg: attachment.alg,
    },
  };
  if (replyTo !== null) payload.r = replyTo;
  return utf8(JSON.stringify(payload));
}

// The peer authenticated these bytes but may still be hostile or buggy: a
// field of the wrong type is a PayloadFormatError, never a crash. An unknown
// kind falls back to the envelope's, as on mobile.
export function decodeInnerPayload(bytes, { fallbackKind }) {
  let decoded;
  try {
    decoded = JSON.parse(fromUtf8(bytes));
  } catch {
    throw new PayloadFormatError('inner payload is not JSON');
  }
  if (decoded === null || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new PayloadFormatError('inner payload is not a JSON object');
  }
  const isV2 = decoded.pv === INNER_PAYLOAD_VERSION;
  const kindName = decoded[isV2 ? 'k' : 'kind'];
  return {
    body: text(decoded, isV2 ? 'b' : 'body'),
    kind: MESSAGE_KINDS.includes(kindName) ? kindName : fallbackKind,
    expiresAt: isV2 ? epochMillis(decoded.x) : isoMillis(decoded.expiresAt),
    attachment: attachmentPointer(decoded.att),
    replyTo: isV2 ? optionalText(decoded, 'r') : null,
  };
}

function text(map, key, fallback = '') {
  const value = map[key];
  if (value === undefined || value === null) return fallback;
  if (typeof value === 'string') return value;
  throw new PayloadFormatError(`inner payload field "${key}" is not a string`);
}

const optionalText = (map, key) => (map[key] === undefined || map[key] === null ? null : text(map, key));

function size(map, key) {
  const value = map[key];
  if (value === undefined || value === null) return 0;
  if (Number.isSafeInteger(value) && value >= 0) return value;
  throw new PayloadFormatError(`inner payload field "${key}" is not a non-negative integer`);
}

function epochMillis(value) {
  if (!Number.isInteger(value)) return null;
  if (Math.abs(value) > MAX_EPOCH_MS) throw new PayloadFormatError('inner payload field "x" is out of range');
  return value;
}

function isoMillis(value) {
  if (typeof value !== 'string') return null;
  const millis = Date.parse(value);
  return Number.isNaN(millis) ? null : millis;
}

// The v2 pointer, or the legacy short form (id, sk, ct, sz, h, ek, n, ah) and
// long form (attachmentId, storageKey, ...), normalized to v2 field names.
function attachmentPointer(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  if ('ck' in raw) {
    return {
      id: text(raw, 'id'),
      ck: text(raw, 'ck'),
      n: text(raw, 'n'),
      d: text(raw, 'd'),
      ct: text(raw, 'ct', 'application/octet-stream'),
      sz: size(raw, 'sz'),
      alg: optionalText(raw, 'alg'),
    };
  }
  const long = 'attachmentId' in raw;
  return {
    id: text(raw, long ? 'attachmentId' : 'id'),
    ck: text(raw, long ? 'encryptedKey' : 'ek'),
    n: text(raw, long ? 'nonce' : 'n'),
    d: text(raw, long ? 'sha256' : 'h'),
    ct: text(raw, long ? 'contentType' : 'ct', 'application/octet-stream'),
    sz: size(raw, long ? 'sizeBytes' : 'sz'),
    alg: optionalText(raw, long ? 'algorithmHint' : 'ah'),
  };
}
