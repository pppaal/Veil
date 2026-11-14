// The decrypted content of one message: what the content store keeps
// (src/platform/content-store.js) and what every view is built from.
//
//   { kind, text, replyTo, attachment, legacyMedia, reaction, expiresAt, legacy }
//
//   kind         'text' | 'reply' | 'image' | 'file' | 'voice' | 'reaction'
//                | 'system' | 'unsupported'
//   text         the message text; a file's (sanitized) name
//   attachment   the protocol-v2 pointer { id, ck, n, d, ct, sz, alg }
//   legacyMedia  media of a retired v1-dev message, bytes as b64u
//   reaction     { target, emoji, op } of a reaction control message
//   expiresAt    the authenticated expiry (ms), or null
//   legacy       read from a retired format: not forward-secret, sender
//                not authenticated
//
// Kinds map onto the MessageKind names both clients share: a reply is a
// 'text' whose payload names the message it answers.

import { encodeBase64Url } from '../core/base64url.js';
import { decodePayload, isAttachmentId } from './payload.js';
import { decodeReaction, encodeReaction } from './reactions.js';
import { sanitizeFilename } from './sanitize.js';

const MEDIA_KINDS = new Set(['image', 'file', 'voice']);
const MESSAGE_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

const content = (fields) => ({
  kind: 'unsupported',
  text: '',
  replyTo: null,
  attachment: null,
  legacyMedia: null,
  reaction: null,
  expiresAt: null,
  legacy: false,
  ...fields,
});

export const textContent = (text, replyTo = null) => content({ kind: replyTo ? 'reply' : 'text', text, replyTo });

export const mediaContent = (kind, attachment, name = '') =>
  content({ kind, attachment, text: kind === 'file' ? sanitizeFilename(name) : '' });

export const reactionContent = (reaction) => content({ kind: 'reaction', reaction });

// An authenticated inner payload (src/crypto/payload-v2.js) as content. A
// peer controls every field, so anything that does not fit its kind is
// unsupported rather than shown raw. That includes an attachment whose id is
// not a UUID: rendering fetches media by that id from the relay with this
// device's credentials, and a path like '../keys/<handle>?claim=all#' would
// otherwise make it call whatever API the peer chose.
export function contentFromPayload(payload) {
  const expiresAt = payload.expiresAt;
  switch (payload.kind) {
    case 'text': {
      const replyTo = MESSAGE_ID_RE.test(payload.replyTo ?? '') ? payload.replyTo : null;
      return { ...textContent(payload.body, replyTo), expiresAt };
    }
    case 'system':
      return content({ kind: 'system', text: payload.body, expiresAt });
    case 'reaction':
      return { ...reactionContent(decodeReaction(payload.body)), expiresAt };
    case 'image':
    case 'file':
    case 'voice':
      return isAttachmentId(payload.attachment?.id)
        ? { ...mediaContent(payload.kind, payload.attachment, payload.body), expiresAt }
        : content({ expiresAt });
    default:
      return content({ expiresAt });
  }
}

// The authenticated expiry (ms) of a message sent at nowMs in a conversation
// whose disappearing timer is timerSeconds, or null without a timer.
export const disappearingExpiry = (timerSeconds, nowMs) =>
  (Number.isInteger(timerSeconds) && timerSeconds > 0 ? nowMs + timerSeconds * 1000 : null);

// The inner payload that carries this content. Its expiry is sealed as "x"
// (contract C4): receivers expire the message at the earlier of it and the
// relay's outer expiresAt, so a relay that drops or extends the outer one
// cannot keep the message around.
export function payloadFromContent(item) {
  const expiresAt = Number.isFinite(item.expiresAt) ? item.expiresAt : null;
  switch (item.kind) {
    case 'text':
    case 'reply':
      return { body: item.text, kind: 'text', replyTo: item.replyTo, expiresAt };
    case 'reaction':
      return { body: encodeReaction(item.reaction), kind: 'reaction', expiresAt };
    default:
      if (!MEDIA_KINDS.has(item.kind) || !item.attachment) throw new TypeError(`cannot send ${item.kind} content`);
      return { body: item.text, kind: item.kind, attachment: item.attachment, expiresAt };
  }
}

// A retired v1-dev plaintext (src/domain/payload.js) as content.
export function contentFromLegacy(plaintext) {
  const decoded = decodePayload(plaintext);
  const fields = { kind: decoded.kind, replyTo: decoded.replyTo, legacy: true };
  const media = decoded.media;
  if (!media) return content({ ...fields, text: decoded.kind === 'unsupported' ? '' : decoded.displayText });
  const b64 = (bytes) => (bytes ? encodeBase64Url(bytes) : undefined);
  return content({
    ...fields,
    text: media.kind === 'file' ? media.name : '',
    legacyMedia: {
      kind: media.kind,
      attachmentId: media.attachmentId,
      key: b64(media.key),
      nonce: b64(media.nonce),
      name: media.name,
      sizeBytes: media.sizeBytes,
      mime: media.mime,
      audio: b64(media.audio),
    },
  });
}
