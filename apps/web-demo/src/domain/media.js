// Lazily materialized message media. Attachment keys live in private class
// fields: a handle can be cached, compared and passed around without the key
// ever being an enumerable (so serializable or loggable) property.

import { fileExtension, sanitizeAudioMime, sniffImageMime } from './sanitize.js';

export class UnsupportedMediaError extends Error {
  constructor(message) {
    super(message);
    this.name = 'UnsupportedMediaError';
  }
}

// Image or file stored as an encrypted attachment blob. materialize()
// downloads and decrypts it on demand.
class AttachmentMedia {
  #key;
  #nonce;
  #deps;

  constructor(descriptor, deps) {
    this.kind = descriptor.kind;
    this.attachmentId = descriptor.attachmentId;
    if (descriptor.kind === 'file') {
      this.name = descriptor.name;
      this.extension = fileExtension(descriptor.name);
      this.sizeBytes = descriptor.sizeBytes;
    }
    this.#key = descriptor.key;
    this.#nonce = descriptor.nonce;
    this.#deps = deps;
  }

  // Images are typed by their magic bytes and refused unless JPEG, PNG or
  // WebP; files are always application/octet-stream so the browser
  // downloads them instead of rendering them in our origin.
  async materialize() {
    const { subtle, fetchAttachment } = this.#deps;
    const sealed = await fetchAttachment(this.attachmentId);
    const key = await subtle.importKey('raw', this.#key, { name: 'AES-GCM' }, false, ['decrypt']);
    const bytes = new Uint8Array(await subtle.decrypt({ name: 'AES-GCM', iv: this.#nonce }, key, sealed));
    if (this.kind !== 'image') return new Blob([bytes], { type: 'application/octet-stream' });
    const mime = sniffImageMime(bytes);
    if (!mime) throw new UnsupportedMediaError('image is not JPEG, PNG or WebP');
    return new Blob([bytes], { type: mime });
  }
}

// Voice note whose audio rode inside the (already decrypted) payload, so
// materializing it never decrypts again.
class InlineAudioMedia {
  #audio;

  constructor(descriptor) {
    this.kind = 'voice';
    this.mime = sanitizeAudioMime(descriptor.mime);
    this.durationMs = descriptor.durationMs;
    this.#audio = descriptor.audio;
  }

  async materialize() {
    return new Blob([this.#audio], { type: this.mime });
  }
}

// deps: { subtle, fetchAttachment(attachmentId) -> Promise<ArrayBuffer> }.
export function createMediaHandle(descriptor, deps) {
  return descriptor.kind === 'voice'
    ? new InlineAudioMedia(descriptor)
    : new AttachmentMedia(descriptor, deps);
}
