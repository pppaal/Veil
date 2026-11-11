// Lazily materialized message media. Attachment keys live in private class
// fields: a handle can be cached, compared and passed around without a key
// ever being an enumerable (so serializable or loggable) property.

import { decodeBase64Url } from '../core/base64url.js';
import { decryptAttachment } from '../crypto/attachment-v2.js';
import { fileExtension, sanitizeAudioMime, sniffImageMime } from './sanitize.js';

export class UnsupportedMediaError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UnsupportedMediaError';
  }
}

// An encrypted attachment blob, downloaded and decrypted on demand. Images
// are typed by their magic bytes and refused unless JPEG, PNG or WebP; voice
// types are allowlisted; files are always application/octet-stream so the
// browser downloads them instead of rendering them in our origin.
class AttachmentMedia {
  #open;
  #deps;

  constructor({ kind, attachmentId, name, sizeBytes, mime }, open, deps) {
    this.kind = kind;
    this.attachmentId = attachmentId;
    if (kind === 'file') {
      this.name = name;
      this.extension = fileExtension(name);
      this.sizeBytes = sizeBytes;
    }
    if (kind === 'voice') this.mime = sanitizeAudioMime(mime);
    this.#open = open;
    this.#deps = deps;
  }

  async materialize() {
    const sealed = await this.#deps.fetchAttachment(this.attachmentId);
    const bytes = await this.#open(this.#deps.subtle, sealed);
    if (this.kind === 'voice') return new Blob([bytes], { type: this.mime });
    if (this.kind !== 'image') return new Blob([bytes], { type: 'application/octet-stream' });
    const mime = sniffImageMime(bytes);
    if (!mime) throw new UnsupportedMediaError('image is not JPEG, PNG or WebP');
    return new Blob([bytes], { type: mime });
  }
}

// A legacy voice note whose audio rode inside the (already decrypted)
// payload, so materializing it never decrypts again.
class InlineAudioMedia {
  #audio;

  constructor({ mime, audio }) {
    this.kind = 'voice';
    this.mime = sanitizeAudioMime(mime);
    this.#audio = audio;
  }

  async materialize() {
    return new Blob([this.#audio], { type: this.mime });
  }
}

// The media of a content record (src/domain/content.js), or null.
// deps: { subtle, fetchAttachment(attachmentId) -> Promise<ArrayBuffer> }.
export function createMediaHandle(content, deps) {
  if (content.attachment) {
    const pointer = content.attachment;
    return new AttachmentMedia(
      { kind: content.kind, attachmentId: pointer.id, name: content.text, sizeBytes: pointer.sz, mime: pointer.ct },
      (subtle, sealed) => decryptAttachment(subtle, pointer, sealed),
      deps,
    );
  }
  const legacy = content.legacyMedia;
  if (!legacy) return null;
  if (legacy.kind === 'voice') return new InlineAudioMedia({ mime: legacy.mime, audio: decodeBase64Url(legacy.audio) });
  // Earlier builds sealed blobs with a raw key and no AAD or padding.
  const key = decodeBase64Url(legacy.key);
  const nonce = decodeBase64Url(legacy.nonce);
  return new AttachmentMedia(legacy, async (subtle, sealed) => {
    const aesKey = await subtle.importKey('raw', key, { name: 'AES-GCM' }, false, ['decrypt']);
    return new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aesKey, sealed));
  }, deps);
}
