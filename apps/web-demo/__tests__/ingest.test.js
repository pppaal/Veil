import { describe, expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';

import { encodeBase64Url } from '../src/core/base64url.js';
import { DELETED_TEXT, ingestMessage, LOCKED_LABELS, previewLabel } from '../src/domain/ingest.js';
import { UnsupportedMediaError } from '../src/domain/media.js';
import { encodePayload, KIND_LABELS, UNSUPPORTED_TEXT } from '../src/domain/payload.js';
import { serializeMessageForCache } from '../src/platform/persist.js';

const { subtle } = webcrypto;
const ATTACHMENT_ID = '3f2b8c1e-5d4a-4c3b-9a8f-1e2d3c4b5a69';
const KEY = Uint8Array.from({ length: 32 }, (_, i) => 31 - i);
const NONCE = Uint8Array.from({ length: 12 }, (_, i) => i);
const PNG = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13]);

// Stand-in for the envelope crypto: ciphertext strings map to payloads.
function decryptTable(entries) {
  return vi.fn(async (raw) => (raw.ciphertext in entries ? { payload: entries[raw.ciphertext] } : { failure: 'failed' }));
}

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
  'ct-text': encodePayload({ kind: 'text', text: 'hi *there*' }),
  'ct-reply': encodePayload({ kind: 'reply', text: 'agreed', replyTo: 'm-0' }),
  'ct-image': encodePayload({ kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY, nonce: NONCE }),
  'ct-file': encodePayload({
    kind: 'file', attachmentId: ATTACHMENT_ID, mime: 'text/html', name: 'notes.html', sizeBytes: 9, key: KEY, nonce: NONCE,
  }),
  'ct-voice': encodePayload({ kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 1200, audio: Uint8Array.of(1, 2, 3) }),
  'ct-edited-reply': encodePayload({ kind: 'reply', text: 'fixed typo', replyTo: 'm-0' }),
  'ct-junk': '{"kind":"image","key":"AAAA"}',
};

describe('ingestMessage', () => {
  it('live and cache inputs yield identical MessageView', async () => {
    const decrypt = decryptTable(PAYLOADS);
    for (const [ciphertext, messageType] of [
      ['ct-text', 'text'], ['ct-reply', 'text'], ['ct-image', 'image'], ['ct-file', 'file'], ['ct-voice', 'voice'], ['ct-junk', 'image'],
    ]) {
      const live = serverSummary({ ciphertext, messageType });
      // What IndexedDB hands back after a reload.
      const cached = structuredClone(serializeMessageForCache({ ...live, _plaintext: 'stale', _imageUrl: 'blob:x' }));
      const fromLive = await ingestMessage(live, { decrypt, media: {} });
      const fromCache = await ingestMessage(cached, { decrypt, media: {} });
      expect(fromCache).toEqual(fromLive);
      expect(fromLive).not.toHaveProperty('deliveredAt');
      expect(fromLive).not.toHaveProperty('attachment');
    }
  });

  it('edited reply shows text not JSON', async () => {
    const decrypt = decryptTable(PAYLOADS);
    const original = await ingestMessage(serverSummary({ ciphertext: 'ct-reply' }), { decrypt, media: {} });
    const edited = await ingestMessage(
      serverSummary({ ciphertext: 'ct-edited-reply', nonce: 'n-2', editedAt: '2026-11-11T09:05:00.000Z' }),
      { decrypt, media: {}, previous: original },
    );
    expect(edited.kind).toBe('reply');
    expect(edited.displayText).toBe('fixed typo');
    expect(edited.replyTo).toBe('m-0');
    expect(edited.displayText).not.toContain('{');
    expect(edited.editedAt).toBe('2026-11-11T09:05:00.000Z');
  });

  it('reuses the decoded content while the ciphertext is unchanged', async () => {
    const decrypt = decryptTable(PAYLOADS);
    const first = await ingestMessage(serverSummary({ ciphertext: 'ct-image', messageType: 'image' }), { decrypt, media: {} });
    const again = await ingestMessage(
      serverSummary({ ciphertext: 'ct-image', messageType: 'image', readAt: 'later' }),
      { decrypt, media: {}, previous: first },
    );
    expect(decrypt).toHaveBeenCalledTimes(1);
    expect(again.media).toBe(first.media);
  });

  it('decrypts again when a known ciphertext arrives under another sender device or conversation', async () => {
    const decrypt = decryptTable({ 'ct-text': 'from the peer' });
    const first = await ingestMessage(serverSummary({}), { decrypt, media: {} });
    // The real decrypt fails here because the AAD names the original sender.
    const rebound = vi.fn(async () => ({ failure: 'failed' }));
    for (const overrides of [{ senderDeviceId: 'd-mallory' }, { conversationId: 'c-2' }]) {
      const moved = await ingestMessage(serverSummary(overrides), { decrypt: rebound, media: {}, previous: first });
      expect(moved).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS.failed });
    }
    expect(rebound).toHaveBeenCalledTimes(2);
  });

  it('retries locked messages instead of reusing them', async () => {
    const decrypt = vi.fn()
      .mockResolvedValueOnce({ failure: 'no-key' })
      .mockResolvedValueOnce({ payload: 'now readable' });
    const locked = await ingestMessage(serverSummary({}), { decrypt, media: {} });
    expect(locked).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS['no-key'] });
    const retried = await ingestMessage(serverSummary({}), { decrypt, media: {}, previous: locked });
    expect(retried).toMatchObject({ kind: 'text', displayText: 'now readable' });
  });

  it('maps deletions and failures to fixed labels without decrypting deletions', async () => {
    const decrypt = vi.fn(async () => { throw new Error('boom'); });
    const deleted = await ingestMessage(serverSummary({ deletedAt: '2026-11-11T10:00:00Z', ciphertext: 'deleted' }), { decrypt, media: {} });
    expect(deleted).toMatchObject({ kind: 'deleted', displayText: DELETED_TEXT, media: null });
    expect(decrypt).not.toHaveBeenCalled();
    const failed = await ingestMessage(serverSummary({}), { decrypt, media: {} });
    expect(failed).toMatchObject({ kind: 'locked', displayText: LOCKED_LABELS.failed });
    const unsupported = await ingestMessage(serverSummary({ ciphertext: 'ct-junk' }), { decrypt: decryptTable(PAYLOADS), media: {} });
    expect(unsupported).toMatchObject({ kind: 'unsupported', displayText: UNSUPPORTED_TEXT });
  });

  it('keeps attachment keys out of the view', async () => {
    const decrypt = decryptTable(PAYLOADS);
    for (const ciphertext of ['ct-image', 'ct-file', 'ct-voice']) {
      const view = await ingestMessage(serverSummary({ ciphertext }), { decrypt, media: {} });
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
    const decrypt = decryptTable(PAYLOADS);

    const image = await ingestMessage(serverSummary({ ciphertext: 'ct-image', messageType: 'image' }), { decrypt, media });
    expect(fetchAttachment).not.toHaveBeenCalled();
    const imageBlob = await image.media.materialize();
    expect(fetchAttachment).toHaveBeenCalledWith(ATTACHMENT_ID);
    expect(imageBlob.type).toBe('image/png');
    expect(new Uint8Array(await imageBlob.arrayBuffer())).toEqual(PNG);

    fetchAttachment.mockResolvedValueOnce(sealedSvg);
    await expect(image.media.materialize()).rejects.toBeInstanceOf(UnsupportedMediaError);

    const file = await ingestMessage(serverSummary({ ciphertext: 'ct-file', messageType: 'file' }), { decrypt, media });
    expect(file.media).toMatchObject({ name: 'notes.html', extension: 'html', sizeBytes: 9 });
    expect((await file.media.materialize()).type).toBe('application/octet-stream');

    const voice = await ingestMessage(serverSummary({ ciphertext: 'ct-voice', messageType: 'voice' }), { decrypt, media });
    const audio = await voice.media.materialize();
    expect(audio.type).toBe('audio/webm');
    expect(new Uint8Array(await audio.arrayBuffer())).toEqual(Uint8Array.of(1, 2, 3));
    expect(decrypt).toHaveBeenCalledTimes(3);
  });
});

describe('previewLabel', () => {
  it('shows text for text kinds and a kind label for everything else', async () => {
    const decrypt = decryptTable(PAYLOADS);
    const view = (ciphertext) => ingestMessage(serverSummary({ ciphertext }), { decrypt, media: {} });
    expect(previewLabel(await view('ct-text'))).toBe('hi *there*');
    expect(previewLabel(await view('ct-reply'))).toBe('agreed');
    expect(previewLabel(await view('ct-image'))).toBe(KIND_LABELS.image);
    expect(previewLabel(await view('ct-file'))).toBe(KIND_LABELS.file);
    expect(previewLabel(await view('ct-voice'))).toBe(KIND_LABELS.voice);
    expect(previewLabel({ kind: 'text', displayText: 'x'.repeat(200) })).toHaveLength(121);
  });
});
