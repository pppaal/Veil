// The single path from an envelope to what the UI shows. Live socket
// events, history refreshes, cache hydration and edits all go through
// ingestMessage, and content comes only from open(raw): the decrypt-once
// store, or a decryption whose result that store keeps
// (src/features/secure-messaging.js). Attachment keys can only end up inside
// a media handle, never in displayText.
//
// A MessageView is the cached envelope fields plus the decoded content:
//   { ...CACHED_MESSAGE_FIELDS, kind, displayText, replyTo, media, legacy,
//     reaction, expiresAtMs }
// kind is a content kind (src/domain/content.js), 'locked' (could not be
// opened), 'deleted', 'expired' (past its expiry, or retired by this device
// and served again) or 'cleared' (history this device deleted). Because the
// view is built from the cached fields only, a live summary and its cached
// copy yield the same view.
//
// Whichever path brings a message here in a deleted or expired state, what
// this device kept of it is retired there and then (options.retire): a
// tombstone fetched by a history poll purges as surely as a realtime event.

import { effectiveExpiry, isPast } from '../core/expiry.js';
import { serializeMessageForCache } from '../platform/persist.js';
import { createMediaHandle } from './media.js';
import { KIND_LABELS, UNSUPPORTED_TEXT } from './payload.js';

export const DELETED_TEXT = '🚫 삭제된 메시지';
export const LOCKED_LABELS = Object.freeze({
  legacy: '🔒 이전 형식',
  'no-key': '🔒 키 미해결',
  failed: '🔒 복호화 실패',
  identityRejected: '🔒 보안 키 변경 — 확인 필요',
  sessionMissing: '🔒 세션 없음',
  'own-missing': '🔒 이 기기에 내용 없음',
});
const PREVIEW_MAX_CHARS = 120;
// Views with nothing left to show: no bubble, preview or search hit.
const GONE_KINDS = new Set(['cleared', 'expired']);

// options.open(raw) resolves to { content } or { failure } (a key of
// LOCKED_LABELS, or 'cleared' or 'retired'). options.retire(raw) drops what
// was kept of a deleted or expired message. options.media is handed to media
// handles for lazy download. options.previous is the current view of the
// same message: when the ciphertext and everything its decryption is bound
// to are unchanged, its content is reused instead of opening it again, which
// keeps blob URLs alive across refreshes. options.now is the time expiries
// are judged at.
export async function ingestMessage(raw, { open, retire, media, previous = null, now = Date.now() }) {
  const envelope = serializeMessageForCache(raw);
  if (raw.deletedAt) {
    // A view that is already a tombstone was retired when it became one.
    if (previous?.kind !== 'deleted') await retire(raw);
    return view(envelope, { kind: 'deleted', displayText: DELETED_TEXT });
  }
  const opened = await openView(envelope, raw, { open, media, previous });
  if (!isPast(opened.expiresAtMs, now)) return opened;
  await retire(raw);
  return view(envelope, { kind: 'expired', displayText: '' });
}

async function openView(envelope, raw, { open, media, previous }) {
  if (previous && previous.kind !== 'locked' && sameSealedContent(previous, raw)) {
    // The relay can bring an expiry forward, never push it back.
    const expiresAtMs = GONE_KINDS.has(previous.kind) ? null : effectiveExpiry(previous.expiresAtMs, envelope.expiresAt);
    return view(envelope, { ...previous, expiresAtMs });
  }
  const result = await Promise.resolve()
    .then(() => open(raw))
    .catch(() => ({ failure: 'failed' }));
  // History this device deleted, or a message it retired, is not a failure
  // to show.
  if (result?.failure === 'cleared') return view(envelope, { kind: 'cleared', displayText: '' });
  if (result?.failure === 'retired') return view(envelope, { kind: 'expired', displayText: '' });
  if (!result?.content) {
    return view(envelope, {
      kind: 'locked',
      displayText: LOCKED_LABELS[result?.failure] ?? LOCKED_LABELS.failed,
      expiresAtMs: effectiveExpiry(null, envelope.expiresAt),
    });
  }
  return contentView(envelope, result.content, media);
}

function contentView(envelope, content, media) {
  return view(envelope, {
    kind: content.kind,
    displayText: displayTextOf(content),
    replyTo: content.replyTo,
    media: createMediaHandle(content, media),
    legacy: content.legacy,
    reaction: content.reaction,
    expiresAtMs: effectiveExpiry(content.expiresAt, envelope.expiresAt),
  });
}

export function isTextKind(kind) {
  return kind === 'text' || kind === 'reply';
}

// Whether nothing of this message may show any more: it has expired (by
// now, even before a sweep turns it into an 'expired' view) or is history
// this device deleted.
export function isGone(message, now = Date.now()) {
  return GONE_KINDS.has(message.kind) || isPast(message.expiresAtMs, now);
}

// Whether a conversation panel shows this message as a bubble. A reaction
// never is one: it changes what its target shows.
export function isShown(message, now = Date.now()) {
  return message.kind !== 'reaction' && !isGone(message, now);
}

// What the sidebar and notifications may show: the text of a text message,
// a kind label for everything else, never a payload, and nothing at all for
// a message that is gone.
export function previewLabel(message, now = Date.now()) {
  if (isGone(message, now)) return '';
  if (isTextKind(message.kind) || message.kind === 'system') {
    const text = message.displayText;
    return text.length > PREVIEW_MAX_CHARS ? `${text.slice(0, PREVIEW_MAX_CHARS)}…` : text;
  }
  return KIND_LABELS[message.kind] ?? message.displayText;
}

function displayTextOf(content) {
  switch (content.kind) {
    case 'text':
    case 'reply':
    case 'system':
      return content.text;
    case 'file':
      return `📁 ${content.text}`;
    case 'image':
    case 'voice':
    case 'reaction':
      return KIND_LABELS[content.kind];
    default:
      return UNSUPPORTED_TEXT;
  }
}

function view(envelope, {
  kind,
  displayText,
  replyTo = null,
  media = null,
  legacy = false,
  reaction = null,
  expiresAtMs = null,
}) {
  return { ...envelope, kind, displayText, replyTo, media, legacy, reaction, expiresAtMs };
}

// The AAD binds a ciphertext to its conversation and sender device, so a
// summary that moves a known ciphertext to another sender (or conversation)
// must be opened again, where the binding is checked, not reused.
function sameSealedContent(previous, raw) {
  return previous.ciphertext === raw.ciphertext
    && previous.nonce === raw.nonce
    && previous.conversationId === raw.conversationId
    && previous.senderDeviceId === raw.senderDeviceId;
}
