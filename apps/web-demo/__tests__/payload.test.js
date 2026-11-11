import { describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { decodePayload, encodePayload, KIND_LABELS, UNSUPPORTED_TEXT } from '../src/domain/payload.js';

const ATTACHMENT_ID = '3f2b8c1e-5d4a-4c3b-9a8f-1e2d3c4b5a69';
const KEY = Uint8Array.from({ length: 32 }, (_, i) => i + 1);
const NONCE = Uint8Array.from({ length: 12 }, (_, i) => 200 + i);
const AUDIO = Uint8Array.from([0x1a, 0x45, 0xdf, 0xa3, 0x01, 0x02]);

const SAMPLES = {
  text: { kind: 'text', text: 'hello *world*' },
  reply: { kind: 'reply', text: 'answer', replyTo: '9b1d6a4e-0c55-4d1c-8e8e-3a1f1f0e0b11' },
  image: { kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY, nonce: NONCE },
  file: {
    kind: 'file',
    attachmentId: ATTACHMENT_ID,
    mime: 'application/pdf',
    name: 'report.pdf',
    sizeBytes: 12345,
    key: KEY,
    nonce: NONCE,
  },
  voice: { kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 2400, audio: AUDIO },
};

const KEY_TEXT = encodeBase64Url(KEY);
const NONCE_TEXT = encodeBase64Url(NONCE);

describe('payload codec', () => {
  it('round-trips every kind', () => {
    expect(decodePayload(encodePayload(SAMPLES.text))).toEqual({ kind: 'text', displayText: 'hello *world*', replyTo: null });
    expect(decodePayload(encodePayload(SAMPLES.reply))).toEqual({
      kind: 'reply',
      displayText: 'answer',
      replyTo: SAMPLES.reply.replyTo,
    });

    const image = decodePayload(encodePayload(SAMPLES.image));
    expect(image).toMatchObject({ kind: 'image', displayText: KIND_LABELS.image, replyTo: null });
    expect(image.media).toEqual({ kind: 'image', attachmentId: ATTACHMENT_ID, key: KEY, nonce: NONCE });

    const file = decodePayload(encodePayload(SAMPLES.file));
    expect(file).toMatchObject({ kind: 'file', displayText: '📁 report.pdf' });
    expect(file.media).toEqual({
      kind: 'file',
      attachmentId: ATTACHMENT_ID,
      name: 'report.pdf',
      sizeBytes: 12345,
      key: KEY,
      nonce: NONCE,
    });

    const voice = decodePayload(encodePayload(SAMPLES.voice));
    expect(voice).toMatchObject({ kind: 'voice', displayText: KIND_LABELS.voice });
    expect(voice.media).toEqual({ kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 2400, audio: AUDIO });
  });

  it('keeps the wire forms earlier web builds send and read', () => {
    expect(encodePayload(SAMPLES.text)).toBe('hello *world*');
    expect(encodePayload(SAMPLES.reply)).toBe(`{"v":1,"text":"answer","replyTo":"${SAMPLES.reply.replyTo}"}`);
    expect(JSON.parse(encodePayload(SAMPLES.image))).toEqual({
      kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY_TEXT, nonce: NONCE_TEXT, width: 0, height: 0,
    });
    expect(Object.keys(JSON.parse(encodePayload(SAMPLES.file))))
      .toEqual(['kind', 'attachmentId', 'mime', 'name', 'sizeBytes', 'key', 'nonce']);
    expect(Object.keys(JSON.parse(encodePayload(SAMPLES.voice)))).toEqual(['kind', 'mime', 'durationMs', 'audio']);
  });

  it('wraps typed text that would parse as a structured payload', () => {
    const lookalike = JSON.stringify({ kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY_TEXT, nonce: NONCE_TEXT });
    const encoded = encodePayload({ kind: 'text', text: lookalike });
    expect(encoded).not.toBe(lookalike);
    expect(decodePayload(encoded)).toEqual({ kind: 'text', displayText: lookalike, replyTo: null });
    expect(decodePayload(encodePayload({ kind: 'text', text: '{"a":1}' }))).toEqual({ kind: 'text', displayText: '{"a":1}', replyTo: null });
  });

  it('malformed becomes unsupported text', () => {
    const malformed = [
      '{"kind":"image"}',
      JSON.stringify({ kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: 'c2hvcnQ', nonce: NONCE_TEXT }),
      JSON.stringify({ kind: 'image', attachmentId: 'not-a-uuid', mime: 'image/png', key: KEY_TEXT, nonce: NONCE_TEXT }),
      JSON.stringify({ kind: 'file', attachmentId: ATTACHMENT_ID, mime: 'x', name: 'a', sizeBytes: -1, key: KEY_TEXT, nonce: NONCE_TEXT }),
      JSON.stringify({ kind: 'voice', mime: 'audio/webm', durationMs: 10, audio: 5 }),
      JSON.stringify({ kind: 'voice', mime: 'audio/webm', durationMs: 10, audio: 'AA', extra: true }),
      JSON.stringify({ kind: 'executable', payload: 'x' }),
      '{"v":2,"text":"future"}',
      '{"v":1,"text":42}',
      '{"v":1,"text":"x","replyTo":"<script>"}',
    ];
    for (const input of malformed) {
      expect(decodePayload(input)).toEqual({ kind: 'unsupported', displayText: UNSUPPORTED_TEXT, replyTo: null });
    }
    expect(decodePayload(null).displayText).toBe(UNSUPPORTED_TEXT);
    expect(decodePayload(undefined).kind).toBe('unsupported');
  });

  it('treats ordinary text, including invalid JSON, as text', () => {
    for (const text of ['plain', '{not json', '[1,2,3]', '{"note":"no tag"}', '']) {
      expect(decodePayload(text)).toEqual({ kind: 'text', displayText: text, replyTo: null });
    }
  });

  it('displayText never contains key material', () => {
    const inputs = [
      encodePayload(SAMPLES.image),
      encodePayload(SAMPLES.file),
      encodePayload(SAMPLES.voice),
      JSON.stringify({ ...JSON.parse(encodePayload(SAMPLES.image)), key: 'c2hvcnQ' }),
      JSON.stringify({ ...JSON.parse(encodePayload(SAMPLES.file)), extra: 'x' }),
      JSON.stringify({ kind: 'mystery', key: KEY_TEXT, nonce: NONCE_TEXT }),
    ];
    for (const input of inputs) {
      const { displayText } = decodePayload(input);
      expect(displayText).not.toContain(KEY_TEXT);
      expect(displayText).not.toContain(NONCE_TEXT);
      expect(displayText).not.toContain('"key"');
      expect(displayText).not.toContain(ATTACHMENT_ID);
    }
  });

  it('sanitizes file names before they reach displayText', () => {
    const decoded = decodePayload(encodePayload({ ...SAMPLES.file, name: 'invoice\u202efdp.exe' }));
    expect(decoded.displayText).toBe('📁 invoicefdp.exe');
    expect(decoded.media.name).toBe('invoicefdp.exe');
  });

  it('refuses to encode invalid payloads', () => {
    expect(() => encodePayload({ kind: 'image', ...SAMPLES.image, attachmentId: 'nope' })).toThrow(TypeError);
    expect(() => encodePayload({ kind: 'reply', text: 'x', replyTo: null })).toThrow(TypeError);
    expect(() => encodePayload({ kind: 'sticker' })).toThrow(TypeError);
    expect(() => encodePayload({ kind: 'text', text: 5 })).toThrow(TypeError);
  });
});
