// Decoder for the plaintext inside a retired v1-dev envelope
// (src/crypto/legacy-v1dev.js), in the forms earlier web builds sent, so
// their history stays readable:
//   text   plain UTF-8 string
//   reply  {"v":1,"text":…,"replyTo":<messageId>}
//   image  {"kind":"image","attachmentId","mime","key","nonce","width","height"}
//   file   {"kind":"file","attachmentId","mime","name","sizeBytes","key","nonce"}
//   voice  {"kind":"voice","mime","durationMs","audio"}
// Anything that claims a structure but fails its schema decodes to
// '[unsupported message]', never to raw JSON: raw JSON of an image or file
// payload would put the attachment key on screen.

import { decodeBase64Url } from '../core/base64url.js';
import { sanitizeFilename } from './sanitize.js';

export const UNSUPPORTED_TEXT = '[unsupported message]';
export const KIND_LABELS = Object.freeze({
  image: '🖼 이미지',
  file: '📁 파일',
  voice: '🎤 음성',
  reaction: '💬 반응',
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
const isCount = (value) => Number.isSafeInteger(value) && value >= 0;
// Every attachment id the relay and both clients create is a UUID, and one
// names a blob in a relay URL, so nothing else is accepted from a peer.
export const isAttachmentId = (value) => typeof value === 'string' && ATTACHMENT_ID_RE.test(value);
const isBase64Url = (length) => (value) => {
  try {
    const bytes = decodeBase64Url(value);
    return length === undefined ? bytes.length > 0 : bytes.length === length;
  } catch {
    return false;
  }
};

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

function media(displayText, descriptor) {
  return { kind: descriptor.kind, displayText, replyTo: null, media: descriptor };
}

function unsupported() {
  return { kind: 'unsupported', displayText: UNSUPPORTED_TEXT, replyTo: null };
}
