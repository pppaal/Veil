import { describe, expect, it } from 'vitest';

import { fileExtension, sanitizeAudioMime, sanitizeFilename, sniffImageMime } from '../src/domain/sanitize.js';

describe('sanitizeFilename', () => {
  it('strips bidi overrides so the real extension cannot hide', () => {
    expect(sanitizeFilename('invoice\u202efdp.exe')).toBe('invoicefdp.exe');
    expect(fileExtension(sanitizeFilename('invoice\u202efdp.exe'))).toBe('exe');
    expect(sanitizeFilename('a\u202ab\u202bc\u202cd\u202de.txt')).toBe('abcde.txt');
    expect(sanitizeFilename('x\u2066y\u2067z\u2068w\u2069.png')).toBe('xyzw.png');
    expect(sanitizeFilename('left\u200eright\u200f.pdf')).toBe('leftright.pdf');
  });

  it('strips C0 and C1 control characters', () => {
    expect(sanitizeFilename('re\u0000port\u0007\u001b.pdf')).toBe('report.pdf');
    expect(sanitizeFilename('tab\there\nnew\u007f\u0085\u009f.doc')).toBe('tabherenew.doc');
  });

  it('caps the length at 120 characters and keeps the extension', () => {
    const long = `${'a'.repeat(300)}.pdf`;
    const cleaned = sanitizeFilename(long);
    expect(Array.from(cleaned)).toHaveLength(120);
    expect(cleaned.endsWith('.pdf')).toBe(true);
    const emoji = sanitizeFilename(`${'😀'.repeat(200)}.zip`);
    expect(Array.from(emoji)).toHaveLength(120);
    expect(emoji.endsWith('.zip')).toBe(true);
    expect(Array.from(sanitizeFilename('b'.repeat(500)))).toHaveLength(120);
    expect(sanitizeFilename(`${'c'.repeat(300)}.PDF`).endsWith('.PDF')).toBe(true);
  });

  it('falls back when nothing printable is left', () => {
    expect(sanitizeFilename('\u202e\u0000')).toBe('file');
    expect(sanitizeFilename(undefined)).toBe('file');
    expect(sanitizeFilename('   ')).toBe('file');
  });

  it('reports only a plausible last extension', () => {
    expect(fileExtension('archive.tar.GZ')).toBe('gz');
    expect(fileExtension('.bashrc')).toBe('');
    expect(fileExtension('no-extension')).toBe('');
    expect(fileExtension('weird.ext with space')).toBe('');
  });
});

describe('sniffImageMime', () => {
  it('accepts JPEG, PNG and WebP magic bytes only', () => {
    expect(sniffImageMime(Uint8Array.of(0xff, 0xd8, 0xff, 0xe0, 0x00))).toBe('image/jpeg');
    expect(sniffImageMime(Uint8Array.of(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00))).toBe('image/png');
    const webp = new TextEncoder().encode('RIFF\u0000\u0000\u0000\u0000WEBPVP8 ');
    expect(sniffImageMime(webp)).toBe('image/webp');
    expect(sniffImageMime(webp.buffer)).toBe('image/webp');
  });

  it('rejects SVG, HTML and other payloads labeled as images', () => {
    const encode = (text) => new TextEncoder().encode(text);
    expect(sniffImageMime(encode('<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"/>'))).toBeNull();
    expect(sniffImageMime(encode('<!doctype html><script>alert(1)</script>'))).toBeNull();
    expect(sniffImageMime(encode('GIF89a'))).toBeNull();
    expect(sniffImageMime(encode('RIFF\u0000\u0000\u0000\u0000WAVE'))).toBeNull();
    expect(sniffImageMime(Uint8Array.of(0xff, 0xd8))).toBeNull();
    expect(sniffImageMime(new Uint8Array(0))).toBeNull();
  });
});

describe('sanitizeAudioMime', () => {
  it('keeps recorder formats and replaces anything else', () => {
    expect(sanitizeAudioMime('audio/webm;codecs=opus')).toBe('audio/webm');
    expect(sanitizeAudioMime('audio/ogg; codecs=opus')).toBe('audio/ogg');
    expect(sanitizeAudioMime('audio/mp4')).toBe('audio/mp4');
    expect(sanitizeAudioMime('text/html')).toBe('audio/webm');
    expect(sanitizeAudioMime(undefined)).toBe('audio/webm');
  });
});
