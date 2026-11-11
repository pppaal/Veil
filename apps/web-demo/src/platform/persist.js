// Serializers for everything the client writes to IndexedDB. Each one copies
// an explicit allowlist and never spreads the in-memory object, which also
// carries decrypted text, media handles and blob: URLs that must not reach
// disk.

export const CACHED_MESSAGE_FIELDS = Object.freeze([
  'id',
  'conversationId',
  'senderDeviceId',
  'conversationOrder',
  'ciphertext',
  'nonce',
  'version',
  'messageType',
  'serverReceivedAt',
  'expiresAt',
  'editedAt',
  'deletedAt',
  'replyToMessageId',
]);

const CACHED_CONVERSATION_FIELDS = Object.freeze([
  'id',
  'type',
  'createdAt',
  'disappearingTimerSeconds',
  'useSenderKeys',
  'currentEpoch',
]);
const CACHED_MEMBER_FIELDS = Object.freeze(['userId', 'handle', 'displayName']);

const QUEUED_ENVELOPE_FIELDS = Object.freeze([
  'version',
  'conversationId',
  'senderDeviceId',
  'recipientUserId',
  'ciphertext',
  'nonce',
  'messageType',
  'attachment',
  'expiresAt',
]);

const KAKAO_META_FIELDS = Object.freeze(['id', 'title', 'importedAt', 'messageCount']);

export function serializeMessageForCache(message) {
  return pick(message, CACHED_MESSAGE_FIELDS);
}

// Row of the 'messages' store, keyed by conversation and server order.
export function messageCacheRecord(message) {
  return {
    _key: `${message.conversationId}:${message.conversationOrder}`,
    ...serializeMessageForCache(message),
  };
}

export function serializeConversationForCache(conversation) {
  return {
    ...pick(conversation, CACHED_CONVERSATION_FIELDS),
    members: (conversation.members ?? []).map((member) => pick(member, CACHED_MEMBER_FIELDS)),
    lastMessage: conversation.lastMessage ? serializeMessageForCache(conversation.lastMessage) : null,
  };
}

// Outbound queue rows hold the encrypted envelope only; the plaintext is
// recovered by decrypting the server's echo once the send goes through.
export function outboundQueueEntry({ clientMessageId, conversationId, envelope }) {
  return { clientMessageId, conversationId, envelope: pick(envelope, QUEUED_ENVELOPE_FIELDS), attempts: 0, nextRetryAt: 0 };
}

// Rewrites a queue row from any schema version, dropping the plaintext copy
// earlier builds stored next to the envelope.
export function sanitizeQueuedOutbound(record) {
  return {
    clientMessageId: record.clientMessageId,
    conversationId: record.conversationId,
    envelope: pick(record.envelope ?? {}, QUEUED_ENVELOPE_FIELDS),
    attempts: record.attempts ?? 0,
    nextRetryAt: record.nextRetryAt ?? 0,
  };
}

// The sidebar row for an imported Kakao archive; the messages stay in the
// archive store and are read only when the archive is opened.
export function kakaoArchiveMeta(archive) {
  return pick(archive, KAKAO_META_FIELDS);
}

function pick(source, fields) {
  const out = {};
  for (const field of fields) {
    if (source[field] !== undefined) out[field] = source[field];
  }
  return out;
}
