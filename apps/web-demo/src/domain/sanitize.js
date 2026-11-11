// Guards for sender-controlled attachment metadata. Names and MIME types
// arrive inside the peer's payload, so a hostile sender picks them freely.

// Bidi embeddings/overrides/isolates (U+202A-202E, U+2066-2069), LRM/RLM
// and C0/C1 controls. A right-to-left override turns "invoice‮fdp.exe"
// into what reads as "invoiceexe.pdf".
const UNSAFE_FILENAME_CHARS_RE = /[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g;
const MAX_FILENAME_CHARS = 120;
const EXTENSION_RE = /^[A-Za-z0-9]{1,10}$/;

export function sanitizeFilename(name, fallback = 'file') {
  const cleaned = String(name ?? '').replace(UNSAFE_FILENAME_CHARS_RE, '').trim();
  const chars = Array.from(cleaned);
  if (chars.length === 0) return fallback;
  if (chars.length <= MAX_FILENAME_CHARS) return cleaned;
  const extension = fileExtension(cleaned);
  const suffix = extension ? `.${extension}` : '';
  return chars.slice(0, MAX_FILENAME_CHARS - suffix.length).join('') + suffix;
}

// The real (last) extension, shown next to the name so it cannot hide.
export function fileExtension(name) {
  const dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  const extension = name.slice(dot + 1);
  return EXTENSION_RE.test(extension) ? extension.toLowerCase() : '';
}

// Decrypted images become same-origin blob: URLs, which a user can open in a
// tab, so the type must come from the bytes and never from the sender's
// claim (an "image/png" that is really SVG or HTML would run script there).
export function sniffImageMime(data) {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return 'image/png';
  if (startsWith(bytes, [0x52, 0x49, 0x46, 0x46]) && startsWith(bytes.subarray(8), [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}

const AUDIO_MIME_ALLOW = new Set(['audio/webm', 'audio/ogg', 'audio/mp4']);
const DEFAULT_AUDIO_MIME = 'audio/webm';

// Same reasoning for voice notes: only the recorder formats we produce.
export function sanitizeAudioMime(mime) {
  const base = String(mime ?? '').split(';')[0].trim().toLowerCase();
  return AUDIO_MIME_ALLOW.has(base) ? base : DEFAULT_AUDIO_MIME;
}

function startsWith(bytes, prefix) {
  if (bytes.length < prefix.length) return false;
  return prefix.every((byte, i) => bytes[i] === byte);
}
