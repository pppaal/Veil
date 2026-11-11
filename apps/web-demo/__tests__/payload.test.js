// The decoder for plaintext inside retired 'veil-envelope-v1-dev' envelopes.
// Inputs are the exact wire forms earlier web builds sent.

import { describe, expect, it } from 'vitest';

import { encodeBase64Url } from '../src/core/base64url.js';
import { decodePayload, KIND_LABELS, UNSUPPORTED_TEXT } from '../src/domain/payload.js';

const ATTACHMENT_ID = '3f2b8c1e-5d4a-4c3b-9a8f-1e2d3c4b5a69';
const REPLY_TO = '9b1d6a4e-0c55-4d1c-8e8e-3a1f1f0e0b11';
const KEY = Uint8Array.from({ length: 32 }, (_, i) => i + 1);
const NONCE = Uint8Array.from({ length: 12 }, (_, i) => 200 + i);
const AUDIO = Uint8Array.from([0x1a, 0x45, 0xdf, 0xa3, 0x01, 0x02]);

const KEY_TEXT = encodeBase64Url(KEY);
const NONCE_TEXT = encodeBase64Url(NONCE);

// What earlier builds' encodePayload produced, field order included.
const WIRE = {
  text: 'hello *world*',
  reply: `{"v":1,"text":"answer","replyTo":"${REPLY_TO}"}`,
  image: JSON.stringify({
    kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY_TEXT, nonce: NONCE_TEXT, width: 0, height: 0,
  }),
  file: JSON.stringify({
    kind: 'file', attachmentId: ATTACHMENT_ID, mime: 'application/pdf', name: 'report.pdf', sizeBytes: 12345, key: KEY_TEXT, nonce: NONCE_TEXT,
  }),
  voice: JSON.stringify({ kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 2400, audio: encodeBase64Url(AUDIO) }),
};

describe('legacy payload decoder', () => {
  it('reads every kind earlier builds sent', () => {
    expect(decodePayload(WIRE.text)).toEqual({ kind: 'text', displayText: 'hello *world*', replyTo: null });
    expect(decodePayload(WIRE.reply)).toEqual({ kind: 'reply', displayText: 'answer', replyTo: REPLY_TO });

    const image = decodePayload(WIRE.image);
    expect(image).toMatchObject({ kind: 'image', displayText: KIND_LABELS.image, replyTo: null });
    expect(image.media).toEqual({ kind: 'image', attachmentId: ATTACHMENT_ID, key: KEY, nonce: NONCE });

    const file = decodePayload(WIRE.file);
    expect(file).toMatchObject({ kind: 'file', displayText: '📁 report.pdf' });
    expect(file.media).toEqual({
      kind: 'file',
      attachmentId: ATTACHMENT_ID,
      name: 'report.pdf',
      sizeBytes: 12345,
      key: KEY,
      nonce: NONCE,
    });

    const voice = decodePayload(WIRE.voice);
    expect(voice).toMatchObject({ kind: 'voice', displayText: KIND_LABELS.voice });
    expect(voice.media).toEqual({ kind: 'voice', mime: 'audio/webm;codecs=opus', durationMs: 2400, audio: AUDIO });
  });

  it('reads typed text that earlier builds wrapped because it looked structured', () => {
    const lookalike = JSON.stringify({ kind: 'image', attachmentId: ATTACHMENT_ID, mime: 'image/png', key: KEY_TEXT, nonce: NONCE_TEXT });
    const wrapped = JSON.stringify({ v: 1, text: lookalike, replyTo: null });
    expect(decodePayload(wrapped)).toEqual({ kind: 'text', displayText: lookalike, replyTo: null });
    expect(decodePayload('{"v":1,"text":"{\\"a\\":1}","replyTo":null}')).toEqual({ kind: 'text', displayText: '{"a":1}', replyTo: null });
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
      WIRE.image,
      WIRE.file,
      WIRE.voice,
      JSON.stringify({ ...JSON.parse(WIRE.image), key: 'c2hvcnQ' }),
      JSON.stringify({ ...JSON.parse(WIRE.file), extra: 'x' }),
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
    const decoded = decodePayload(JSON.stringify({ ...JSON.parse(WIRE.file), name: 'invoice‮fdp.exe' }));
    expect(decoded.displayText).toBe('📁 invoicefdp.exe');
    expect(decoded.media.name).toBe('invoicefdp.exe');
  });

  it('reads the empty MIME type earlier builds sent', () => {
    // file.type is '' when the browser knows no type; earlier builds sent it as is.
    for (const wire of [WIRE.image, WIRE.file]) {
      const emptyMime = JSON.stringify({ ...JSON.parse(wire), mime: '' });
      expect(decodePayload(emptyMime).kind).toBe(JSON.parse(wire).kind);
    }
    expect(decodePayload(JSON.stringify({ ...JSON.parse(WIRE.file), mime: 'x/'.repeat(100) })).kind).toBe('unsupported');
  });
});
