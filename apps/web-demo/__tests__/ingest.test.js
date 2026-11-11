import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { encodeBase64Url } from '../src/core/base64url.js';
import { encryptAttachment } from '../src/crypto/attachment-v2.js';
import { decodeInnerPayload, encodeInnerPayload } from '../src/crypto/payload-v2.js';
import { contentFromLegacy, contentFromPayload, mediaContent, textContent } from '../src/domain/content.js';
import { DELETED_TEXT, ingestMessage, LOCKED_LABELS, previewLabel } from '../src/domain/ingest.js';
import { createAttachmentFetcher, UnsupportedMediaError } from '../src/domain/media.js';
import { KIND_LABELS, UNSUPPORTED_TEXT } from '../src/domain/payload.js';
import { serializeMessageForCache } from '../src/platform/persist.js';

const { subtle } = webcrypto;
const ATTACHMENT_ID = '3f2b8c1e-5d4a-4c3b-9a8f-1e2d3c4b5a69';
const KEY = Uint8Array.from({ length: 32 }, (_, i) => 31 - i);
const NONCE = Uint8Array.from({ length: 12 }, (_, i) => i);
const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);

// Stand-in for the decrypt-once store: ciphertext strings map to the content
// of plaintexts in the retired v1-dev wire forms, whose media carry raw keys.
function openTable(entries) {
  return vi.fn(async (raw) => (raw.ciphertext in entries
    ? { content: contentFromLegacy(entries[raw.ciphertext]) }
    : { failure: 'failed' }));
}
const legacyMedia = (fields) => JSON.stringify(fields);

function serverSummary(overrides) {
  return {
    id: 'm-1',
    clientMessageId: 'web-1',
    conversationId: 'c-1',
    senderDeviceId: 'd-peer',
    conversationOrder: 7,
    ciphertext: 'ct-text',
    nonce: 'n-1',
    messageType: 'text',
    serverReceivedAt: '2026-11-11T09:00:00.000Z',
    expiresAt: null,
    editedAt: null,
    deletedAt: null,
    replyToMessageId: null,
    deliveredAt: '2026-11-11T09:00:01.000Z',
    readAt: null,
    reactions: [{ userId: 'u-2', emoji: '👍' }],
    attachment: { attachmentId: ATTACHMENT_ID, storageKey: 'blob/1', sha256: 'abc' },
    ...overrides,
  };
}

const PAYLOADS = {
  'ct-text': 'hi *there*',
  'ct-reply': '{"v":1,"text":"agreed","replyTo":"m-0"}',
  'ct-image': legacyMedia({
    kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: encodeBase64Url(KEY), nonce: encodeBase64Url(NONCE), width: 0, height: 0,
  }),
  'ct-file': legacyMedia({
    kind: 'file', attachmentId: ATTACHMENT_ID, mime: 'text/html', name: 'notes.html', sizeBytes: 9, key: encodeBase64Url(KEY), nonce: encodeBase64Url(NONCE),
  }),
  'ct-voice': legacyMedia({ kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 1200, audio: encodeBase64Url(Uint8Array.of(1, 2, 3)) }),
  'ct-edited-reply': '{"v":1,"text":"fixed typo","replyTo":"m-0"}',
  'ct-junk': '{"kind":"image","key":"AAAA"}',
};

describe('ingestMessage', () => {
  it('live and cache inputs yield identical MessageView', async () => {
    const open = openTable(PAYLOADS);
    for (const [ciphertext, messageType] of [
      ['ct-text', 'text'], ['ct-reply', 'text'], ['ct-image', 'image'], ['ct-file', 'file'], ['ct-voice', 'voice'], ['ct-junk', 'image'],
    ]) {
      const live = serverSummary({ ciphertext, messageType });
      // What IndexedDB hands back after a reload.
      const cached = structuredClone(serializeMessageForCache({ ...live, _plaintext: 'stale', _imageUrl: 'blob:x' }));
      const fromLive = await ingestMessage(live, { open, media: {} });
      const fromCache = await ingestMessage(cached, { open, media: {} });
      expect(fromCache).toEqual(fromLive);
      expect(fromLive).not.toHaveProperty('deliveredAt');
      expect(fromLive).not.toHaveProperty('attachment');
    }
  });

  it('edited reply shows text not JSON', async () => {
    const open = openTable(PAYLOADS);
    const original = await ingestMessage(serverSummary({ ciphertext: 'ct-reply' }), { open, media: {} });
    const edited = await ingestMessage(
      serverSummary({ ciphertext: 'ct-edited-reply', nonce: 'n-2', editedAt: '2026-11-11T09:05:00.000Z' }),
      { open, media: {}, previous: original },
    );
    expect(edited.kind).toBe('reply');
    expect(edited.displayText).toBe('fixed typo');
    expect(edited.replyTo).toBe('m-0');
    expect(edited.displayText).not.toContain('{');
    expect(edited.editedAt).toBe('2026-11-11T09:05:00.000Z');
  });

  it('reuses the decoded content while the ciphertext is unchanged', async () => {
    const open = openTable(PAYLOADS);
    const first = await ingestMessage(serverSummary({ ciphertext: 'ct-image', messageType: 'image' }), { open, media: {} });
    const again = await ingestMessage(
      serverSummary({ ciphertext: 'ct-image', messageType: 'image', readAt: 'later' }),
      { open, media: {}, previous: first },
    );
    expect(open).toHaveBeenCalledTimes(1);
    expect(again.media).toBe(first.media);
  });

  it('decrypts again when a known ciphertext arrives under another sender device or conversation', async () => {
    const open = openTable({ 'ct-text': 'from the peer' });
    const first = await ingestMessage(serverSummary({}), { open, media: {} });
    // The real decrypt fails here because the AAD names the original sender.
    const rebound = vi.fn(async () => ({ failure: 'failed' }));
    for (const overrides of [{ senderDeviceId: 'd-mallory' }, { conversationId: 'c-2' }]) {
      const moved = await ingestMessage(serverSummary(overrides), { open: rebound, media: {}, previous: first });
      expect(moved).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS.failed });
    }
    expect(rebound).toHaveBeenCalledTimes(2);
  });

  it('retries locked messages instead of reusing them', async () => {
    const open = vi.fn()
      .mockResolvedValueOnce({ failure: 'no-key' })
      .mockResolvedValueOnce({ content: textContent('now readable') });
    const locked = await ingestMessage(serverSummary({}), { open, media: {} });
    expect(locked).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS['no-key'] });
    const retried = await ingestMessage(serverSummary({}), { open, media: {}, previous: locked });
    expect(retried).toMatchObject({ kind: 'text', displayText: 'now readable' });
  });

  it('maps deletions and failures to fixed labels without decrypting deletions', async () => {
    const open = vi.fn(async () => { throw new Error('boom'); });
    const deleted = await ingestMessage(serverSummary({ deletedAt: '2026-11-11T10:00:00Z', ciphertext: 'deleted' }), { open, media: {} });
    expect(deleted).toMatchObject({ kind: 'deleted', displayText: DELETED_TEXT, media: null });
    expect(open).not.toHaveBeenCalled();
    const failed = await ingestMessage(serverSummary({}), { open, media: {} });
    expect(failed).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS.failed });
    const unsupported = await ingestMessage(serverSummary({ ciphertext: 'ct-junk' }), { open: openTable(PAYLOADS), media: {} });
    expect(unsupported).toMatchObject({ kind: 'unsupported', displayText: UNSUPPORTED_TEXT });
  });

  it('keeps attachment keys out of the view', async () => {
    const open = openTable(PAYLOADS);
    for (const ciphertext of ['ct-image', 'ct-file', 'ct-voice']) {
      const view = await ingestMessage(serverSummary({ ciphertext }), { open, media: {} });
      const serialized = JSON.stringify(view);
      expect(serialized).not.toContain(encodeBase64Url(KEY));
      expect(serialized).not.toContain('"key"');
      expect(view.displayText).not.toContain(encodeBase64Url(KEY));
    }
  });

  it('materializes media lazily from the payload, typed by content', async () => {
    const aesKey = await subtle.importKey('raw', KEY, { name: 'AES-GCM' }, false, ['encrypt']);
    const sealedPng = await subtle.encrypt({ name: 'AES-GCM', iv: NONCE }, aesKey, PNG);
    const sealedSvg = await subtle.encrypt({ name: 'AES-GCM', iv: NONCE }, aesKey, new TextEncoder().encode('<svg onload=alert(1)>'));
    const fetchAttachment = vi.fn(async () => sealedPng);
    const media = { subtle, fetchAttachment };
    const open = openTable(PAYLOADS);

    const image = await ingestMessage(serverSummary({ ciphertext: 'ct-image', messageType: 'image' }), { open, media });
    expect(fetchAttachment).not.toHaveBeenCalled();
    const imageBlob = await image.media.materialize();
    expect(fetchAttachment).toHaveBeenCalledWith(ATTACHMENT_ID);
    expect(imageBlob.type).toBe('image/png');
    expect(new Uint8Array(await imageBlob.arrayBuffer())).toEqual(PNG);

    fetchAttachment.mockResolvedValueOnce(sealedSvg);
    await expect(image.media.materialize()).rejects.toBeInstanceOf(UnsupportedMediaError);

    const file = await ingestMessage(serverSummary({ ciphertext: 'ct-file', messageType: 'file' }), { open, media });
    expect(file.media).toMatchObject({ name: 'notes.html', extension: 'html', sizeBytes: 9 });
    expect((await file.media.materialize()).type).toBe('application/octet-stream');

    const voice = await ingestMessage(serverSummary({ ciphertext: 'ct-voice', messageType: 'voice' }), { open, media });
    const audio = await voice.media.materialize();
    expect(audio.type).toBe('audio/webm');
    expect(new Uint8Array(await audio.arrayBuffer())).toEqual(Uint8Array.of(1, 2, 3));
    expect(open).toHaveBeenCalledTimes(3);
    expect([image, file, voice].every((view) => view.legacy)).toBe(true);
  });

  it('materializes protocol-v2 attachments only when the blob matches its pointer', async () => {
    const random = (length) => webcrypto.getRandomValues(new Uint8Array(length));
    const { pointer, blob } = await encryptAttachment(subtle, random, {
      attachmentId: ATTACHMENT_ID,
      contentType: 'image/png',
      plaintext: PNG,
    });
    const fetchAttachment = vi.fn(async () => blob.buffer);
    const open = vi.fn(async () => ({ content: mediaContent('image', pointer) }));
    const image = await ingestMessage(serverSummary({ messageType: 'image' }), { open, media: { subtle, fetchAttachment } });
    expect(image).toMatchObject({ kind: 'image', displayText: KIND_LABELS.image, legacy: false });
    expect(JSON.stringify(image)).not.toContain(pointer.ck);
    const decrypted = await image.media.materialize();
    expect(decrypted.type).toBe('image/png');
    expect(new Uint8Array(await decrypted.arrayBuffer())).toEqual(PNG);

    const swapped = blob.slice();
    swapped[3] ^= 0xff;
    fetchAttachment.mockResolvedValueOnce(swapped.buffer);
    await expect(image.media.materialize()).rejects.toThrow('digest');
  });

  it('a peer-chosen attachment id never reaches the relay API', async () => {
    const random = (length) => webcrypto.getRandomValues(new Uint8Array(length));
    const { pointer } = await encryptAttachment(subtle, random, {
      attachmentId: ATTACHMENT_ID,
      contentType: 'image/png',
      plaintext: PNG,
    });
    const authedApi = vi.fn(async () => ({ ticket: { downloadUrl: 'https://blobs.example/1' } }));
    const fetchImpl = vi.fn(async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(0) }));
    const fetchAttachment = createAttachmentFetcher({ authedApi, fetchImpl });
    const hostileId = '../keys/victim?claim=all#';

    // As it arrives: authenticated, from a peer that crafted the pointer.
    const payload = decodeInnerPayload(
      encodeInnerPayload({ body: '', kind: 'image', attachment: { ...pointer, id: hostileId } }),
      { fallbackKind: 'image' },
    );
    const open = vi.fn(async () => ({ content: contentFromPayload(payload) }));
    const image = await ingestMessage(serverSummary({ messageType: 'image' }), { open, media: { subtle, fetchAttachment } });
    expect(image).toMatchObject({ kind: 'unsupported', media: null });

    // Even content stored before ids were checked cannot steer the request.
    for (const id of [hostileId, '..']) {
      await expect(fetchAttachment(id)).rejects.toBeInstanceOf(UnsupportedMediaError);
    }
    expect(authedApi).not.toHaveBeenCalled();

    await fetchAttachment(ATTACHMENT_ID);
    expect(authedApi).toHaveBeenCalledWith(`/attachments/${ATTACHMENT_ID}/download-ticket`);
    expect(fetchImpl).toHaveBeenCalledWith('https://blobs.example/1');
  });

  it('expires at the earlier of the authenticated and the relayed expiry', async () => {
    const inner = Date.parse('2026-11-12T00:00:00.000Z');
    const open = vi.fn(async () => ({ content: { ...textContent('ephemeral'), expiresAt: inner } }));
    const later = await ingestMessage(serverSummary({ expiresAt: '2026-11-13T00:00:00.000Z' }), { open, media: {} });
    const earlier = await ingestMessage(serverSummary({ expiresAt: '2026-11-11T12:00:00.000Z' }), { open, media: {} });
    expect(later.expiresAtMs).toBe(inner);
    expect(earlier.expiresAtMs).toBe(Date.parse('2026-11-11T12:00:00.000Z'));
  });
});

describe('previewLabel', () => {
  it('shows text for text kinds and a kind label for everything else', async () => {
    const open = openTable(PAYLOADS);
    const view = (ciphertext) => ingestMessage(serverSummary({ ciphertext }), { open, media: {} });
    expect(previewLabel(await view('ct-text'))).toBe('hi *there*');
    expect(previewLabel(await view('ct-reply'))).toBe('agreed');
    expect(previewLabel(await view('ct-image'))).toBe(KIND_LABELS.image);
    expect(previewLabel(await view('ct-file'))).toBe(KIND_LABELS.file);
    expect(previewLabel(await view('ct-voice'))).toBe(KIND_LABELS.voice);
    expect(previewLabel({ kind: 'text', displayText: 'x'.repeat(200) })).toHaveLength(121);
  });
});
