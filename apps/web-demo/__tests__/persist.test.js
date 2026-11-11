import { describe, expect, it } from 'vitest';

import {
  CACHED_MESSAGE_FIELDS,
  kakaoArchiveMeta,
  messageCacheRecord,
  outboundQueueEntry,
  sanitizeQueuedOutbound,
  serializeConversationForCache,
  serializeMessageForCache,
} from '../src/platform/persist.js';

// An in-memory message as the app holds it: envelope fields, receipts, and
// the decoded content and transient state that must never reach disk.
function inMemoryMessage() {
  return {
    id: 'm-1',
    conversationId: 'c-1',
    senderDeviceId: 'd-1',
    conversationOrder: 3,
    ciphertext: 'v2.abc',
    nonce: 'nonce',
    version: 'veil-envelope-v1-dev',
    messageType: 'image',
    serverReceivedAt: '2026-11-11T09:00:00.000Z',
    expiresAt: null,
    editedAt: null,
    deletedAt: null,
    replyToMessageId: null,
    clientMessageId: 'img-1',
    deliveredAt: '2026-11-11T09:00:01.000Z',
    reactions: [{ userId: 'u', emoji: '🔥' }],
    attachment: { attachmentId: 'a-1', encryption: { nonce: 'n' } },
    kind: 'image',
    displayText: '🖼 이미지',
    replyTo: 'm-0',
    media: { kind: 'image', attachmentId: 'a-1' },
    _plaintext: '{"kind":"image","key":"SECRET"}',
    _fileMeta: { key: 'SECRET' },
    _imageUrl: 'blob:https://veil/123',
    _status: 'pending',
  };
}

describe('persistence serializers', () => {
  it('serializer drops non-allowlisted fields', () => {
    const record = serializeMessageForCache(inMemoryMessage());
    expect(Object.keys(record).sort()).toEqual([...CACHED_MESSAGE_FIELDS].sort());
    expect(record).toEqual({
      id: 'm-1',
      conversationId: 'c-1',
      senderDeviceId: 'd-1',
      conversationOrder: 3,
      ciphertext: 'v2.abc',
      nonce: 'nonce',
      version: 'veil-envelope-v1-dev',
      messageType: 'image',
      serverReceivedAt: '2026-11-11T09:00:00.000Z',
      expiresAt: null,
      editedAt: null,
      deletedAt: null,
      replyToMessageId: null,
    });
    expect(JSON.stringify(record)).not.toContain('SECRET');
  });

  it('keeps a deleted message as a tombstone without its sealed content', () => {
    const record = serializeMessageForCache({ ...inMemoryMessage(), deletedAt: '2026-11-11T10:00:00.000Z' });
    expect(record).not.toHaveProperty('ciphertext');
    expect(record).not.toHaveProperty('nonce');
    expect(record).toMatchObject({ id: 'm-1', conversationId: 'c-1', deletedAt: '2026-11-11T10:00:00.000Z' });
  });

  it('omits allowlisted fields the source does not have', () => {
    expect(serializeMessageForCache({ id: 'm', conversationId: 'c', extra: 1 })).toEqual({ id: 'm', conversationId: 'c' });
  });

  it('keys message rows by conversation and order', () => {
    const row = messageCacheRecord(inMemoryMessage());
    expect(row._key).toBe('c-1:3');
    expect(row).not.toHaveProperty('displayText');
  });

  it('caches conversations with an allowlisted last message and members', () => {
    const conversation = {
      id: 'c-1',
      type: 'direct',
      createdAt: '2026-11-01T00:00:00.000Z',
      members: [{ userId: 'u-1', handle: 'alice', displayName: 'Alice', secretNote: 'x' }],
      lastMessage: inMemoryMessage(),
      unexpected: 'dropped',
    };
    const record = serializeConversationForCache(conversation);
    expect(record).toEqual({
      id: 'c-1',
      type: 'direct',
      createdAt: '2026-11-01T00:00:00.000Z',
      members: [{ userId: 'u-1', handle: 'alice' }],
      lastMessage: serializeMessageForCache(conversation.lastMessage),
    });
    expect(serializeConversationForCache({ id: 'c-2', members: [] }).lastMessage).toBeNull();
  });

  it('queues only the encrypted envelope', () => {
    const envelope = {
      version: 'veil-envelope-v1-dev',
      conversationId: 'c-1',
      senderDeviceId: 'd-1',
      recipientUserId: 'u-2',
      ciphertext: 'v2.abc',
      nonce: 'n',
      messageType: 'text',
    };
    const entry = outboundQueueEntry({ clientMessageId: 'web-1', conversationId: 'c-1', envelope: { ...envelope, text: 'hello' } });
    expect(entry).toEqual({ clientMessageId: 'web-1', conversationId: 'c-1', envelope, attempts: 0, nextRetryAt: 0 });

    // A row written by an earlier build carried the typed text next to the envelope.
    const legacyRow = { clientMessageId: 'web-1', conversationId: 'c-1', envelope, plaintext: 'hello', attempts: 2, nextRetryAt: 99 };
    expect(sanitizeQueuedOutbound(legacyRow)).toEqual({ ...entry, attempts: 2, nextRetryAt: 99 });
  });

  it('keeps Kakao archive messages out of the sidebar metadata', () => {
    const meta = kakaoArchiveMeta({
      id: 'kakao-1',
      title: 'family',
      importedAt: '2026-11-11T00:00:00.000Z',
      participants: ['a', 'b'],
      messageCount: 2,
      messages: [{ kind: 'msg', body: 'private' }],
    });
    expect(meta).toEqual({ id: 'kakao-1', title: 'family', importedAt: '2026-11-11T00:00:00.000Z', messageCount: 2 });
  });
});
