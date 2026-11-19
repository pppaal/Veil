// Attachment blobs (docs/crypto-envelope-spec.md §Attachments): a fresh key
// and nonce per blob, and a pointer that travels only inside the
// ratchet-encrypted payload, so attachments inherit the session's forward
// secrecy and nothing is wrapped to a static key.
//
//   padded = ISO 7816-4 pad to padmeLength(len + 1)
//   blob   = AES-256-GCM(key, nonce, padded, aad = "veil-att-v2" || utf8(attachmentId))
//   att    = { id, ck: b64u(key), n: b64u(nonce), d: b64u(SHA-256(blob)), ct, sz, alg }
//
// The AAD binds the id, so the id exists before the blob does: the sender
// proposes it (a UUID v4) when asking for the upload ticket.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { concatBytes, constantTimeEqual, utf8, zeroize } from './bytes.js';
import { aesGcmOpen, aesGcmSeal, GCM_NONCE_BYTES, KEY_BYTES, sha256 } from './keys.js';
import { padAttachment, unpad } from './padding.js';

const ATTACHMENT_ALGORITHM_V2 = 'aes256gcm-v2';
const ATTACHMENT_AAD_LABEL = utf8('veil-att-v2');

class AttachmentIntegrityError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AttachmentIntegrityError';
  }
}

const attachmentAad = (attachmentId) => concatBytes([ATTACHMENT_AAD_LABEL, utf8(attachmentId)]);

export async function encryptAttachment(subtle, randomBytes, { attachmentId, contentType, plaintext }) {
  const key = randomBytes(KEY_BYTES);
  const nonce = randomBytes(GCM_NONCE_BYTES);
  const padded = padAttachment(plaintext);
  const blob = await aesGcmSeal(subtle, key, nonce, padded, attachmentAad(attachmentId));
  zeroize(padded);
  const pointer = {
    id: attachmentId,
    ck: encodeBase64Url(key),
    n: encodeBase64Url(nonce),
    d: encodeBase64Url(await sha256(subtle, blob)),
    ct: contentType,
    sz: plaintext.length,
    alg: ATTACHMENT_ALGORITHM_V2,
  };
  zeroize(key);
  return { pointer, blob };
}

// The digest is compared (in constant time) before anything is decrypted, so
// a swapped blob is refused without touching the key.
export async function decryptAttachment(subtle, pointer, blob) {
  const sealed = blob instanceof Uint8Array ? blob : new Uint8Array(blob);
  if (!constantTimeEqual(await sha256(subtle, sealed), decodeOrEmpty(pointer.d))) {
    throw new AttachmentIntegrityError('attachment digest does not match its pointer');
  }
  const key = decodeOrEmpty(pointer.ck);
  const nonce = decodeOrEmpty(pointer.n);
  if (key.length !== KEY_BYTES || nonce.length !== GCM_NONCE_BYTES) {
    throw new AttachmentIntegrityError('attachment key or nonce has the wrong length');
  }
  try {
    return unpad(await aesGcmOpen(subtle, key, nonce, sealed, attachmentAad(pointer.id)));
  } catch {
    throw new AttachmentIntegrityError('attachment failed authentication');
  } finally {
    zeroize(key);
  }
}

function decodeOrEmpty(text) {
  try {
    return decodeBase64Url(text);
  } catch {
    return new Uint8Array(0);
  }
}
