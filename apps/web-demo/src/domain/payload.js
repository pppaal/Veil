// Codec for the plaintext inside a 'veil-envelope-v1-dev' ciphertext. The
// wire forms are the ones earlier web builds send, so mixed-version chats
// keep working:
//   text   plain UTF-8 string
//   reply  {"v":1,"text":…,"replyTo":<messageId>}
//   image  {"kind":"image","attachmentId","mime","key","nonce","width","height"}
//   file   {"kind":"file","attachmentId","mime","name","sizeBytes","key","nonce"}
//   voice  {"kind":"voice","mime","durationMs","audio"}
// Anything that claims a structure but fails its schema decodes to
// '[unsupported message]', never to raw JSON: raw JSON of an image or file
// payload would put the attachment key on screen.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { sanitizeFilename } from './sanitize.js';

export const UNSUPPORTED_TEXT = '[unsupported message]';
export const KIND_LABELS = Object.freeze({
  image: '🖼 이미지',
  file: '📁 파일',
  voice: '🎤 음성',
});

const ATTACHMENT_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MESSAGE_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const KEY_BYTES = 32;
const NONCE_BYTES = 12;

const MIME_MAX_CHARS = 128;

const optional = (check) => (value) => value === undefined || check(value);
const boundedString = (max) => (value) => typeof value === 'string' && value.length > 0 && value.length <= max;
// A MIME type is a hint only: images are typed by their bytes, files download
// as octet-stream and voice types are allowlisted before playback. Earlier
// builds sent '' when the browser knew no type, so empty is valid.
const isMimeHint = (value) => typeof value === 'string' && value.length <= MIME_MAX_CHARS;
// An unusable hint is sent as '' rather than failing the send.
const mimeHint = (value) => (isMimeHint(value) ? value : '');
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;
const isAttachmentId = (value) => typeof value === 'string' && ATTACHMENT_ID_RE.test(value);
const isBase64Url = (length) => (value) => {
  try {
    const bytes = decodeBase64Url(value);
    return length === undefined ? bytes.length > 0 : bytes.length === length;
  } catch {
    return false;
  }
};

// Field order is the wire order; encode emits keys in exactly this order.
const MEDIA_SCHEMAS = {
  image: {
    attachmentId: isAttachmentId,
    mime: isMimeHint,
    key: isBase64Url(KEY_BYTES),
    nonce: isBase64Url(NONCE_BYTES),
    width: optional(isCount),
    height: optional(isCount),
  },
  file: {
    attachmentId: isAttachmentId,
    mime: isMimeHint,
    name: boundedString(1024),
    sizeBytes: isCount,
    key: isBase64Url(KEY_BYTES),
    nonce: isBase64Url(NONCE_BYTES),
  },
  voice: {
    mime: isMimeHint,
    durationMs: isCount,
    audio: isBase64Url(),
  },
};

const REPLY_FIELDS = new Set(['v', 'text', 'replyTo']);

export function encodePayload(payload) {
  switch (payload?.kind) {
    case 'text':
      requireString(payload.text);
      // Prose that would parse as a structured payload is wrapped, so typed
      // text can never be mistaken for media or a reply on the other side.
      return parseStructured(payload.text) === null
        ? payload.text
        : JSON.stringify({ v: 1, text: payload.text, replyTo: null });
    case 'reply':
      requireString(payload.text);
      if (!MESSAGE_ID_RE.test(payload.replyTo ?? '')) throw new TypeError('reply needs a message id');
      return JSON.stringify({ v: 1, text: payload.text, replyTo: payload.replyTo });
    case 'image':
      return encodeMedia({
        kind: 'image',
        attachmentId: payload.attachmentId,
        mime: mimeHint(payload.mime),
        key: encodeBase64Url(payload.key),
        nonce: encodeBase64Url(payload.nonce),
        width: payload.width ?? 0,
        height: payload.height ?? 0,
      });
    case 'file':
      return encodeMedia({
        kind: 'file',
        attachmentId: payload.attachmentId,
        mime: mimeHint(payload.mime),
        name: payload.name,
        sizeBytes: payload.sizeBytes,
        key: encodeBase64Url(payload.key),
        nonce: encodeBase64Url(payload.nonce),
      });
    case 'voice':
      return encodeMedia({
        kind: 'voice',
        mime: mimeHint(payload.mime),
        durationMs: payload.durationMs,
        audio: encodeBase64Url(payload.audio),
      });
    default:
      throw new TypeError(`unsupported payload kind: ${payload?.kind}`);
  }
}

// Returns { kind, displayText, replyTo, media? }. displayText is always safe
// to render and never carries key material; media holds the decoded
// attachment descriptor (key and nonce as bytes) for the media layer.
export function decodePayload(plaintext) {
  if (typeof plaintext !== 'string') return unsupported();
  const structured = parseStructured(plaintext);
  if (structured === null) return { kind: 'text', displayText: plaintext, replyTo: null };
  if ('kind' in structured) return decodeMedia(structured);
  return decodeTextEnvelope(structured);
}

function decodeTextEnvelope(value) {
  if (value.v !== 1 || !hasOnlyFields(value, REPLY_FIELDS) || typeof value.text !== 'string') {
    return unsupported();
  }
  const replyTo = value.replyTo ?? null;
  if (replyTo === null) return { kind: 'text', displayText: value.text, replyTo: null };
  if (typeof replyTo !== 'string' || !MESSAGE_ID_RE.test(replyTo)) return unsupported();
  return { kind: 'reply', displayText: value.text, replyTo };
}

function decodeMedia(value) {
  const schema = MEDIA_SCHEMAS[value.kind];
  if (!schema || !matchesSchema(value, schema)) return unsupported();
  switch (value.kind) {
    case 'image':
      return media(KIND_LABELS.image, {
        kind: 'image',
        attachmentId: value.attachmentId,
        key: decodeBase64Url(value.key),
        nonce: decodeBase64Url(value.nonce),
      });
    case 'file': {
      const name = sanitizeFilename(value.name);
      return media(`📁 ${name}`, {
        kind: 'file',
        attachmentId: value.attachmentId,
        name,
        sizeBytes: value.sizeBytes,
        key: decodeBase64Url(value.key),
        nonce: decodeBase64Url(value.nonce),
      });
    }
    default:
      return media(KIND_LABELS.voice, {
        kind: 'voice',
        mime: value.mime,
        durationMs: value.durationMs,
        audio: decodeBase64Url(value.audio),
      });
  }
}

function encodeMedia(fields) {
  const encoded = JSON.stringify(fields);
  if (decodePayload(encoded).kind !== fields.kind) throw new TypeError(`invalid ${fields.kind} payload`);
  return encoded;
}

// A JSON object carrying a `kind` or `v` tag is a structured payload; any
// other text, JSON-looking or not, is prose.
function parseStructured(text) {
  if (!text.startsWith('{')) return null;
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  return 'kind' in value || 'v' in value ? value : null;
}

function matchesSchema(value, schema) {
  const allowed = new Set(['kind', ...Object.keys(schema)]);
  return hasOnlyFields(value, allowed) && Object.entries(schema).every(([field, check]) => check(value[field]));
}

function hasOnlyFields(value, allowed) {
  return Object.keys(value).every((field) => allowed.has(field));
}

function requireString(text) {
  if (typeof text !== 'string') throw new TypeError('text payload needs a string');
}

function media(displayText, descriptor) {
  return { kind: descriptor.kind, displayText, replyTo: null, media: descriptor };
}

function unsupported() {
  return { kind: 'unsupported', displayText: UNSUPPORTED_TEXT, replyTo: null };
}
