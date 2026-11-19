// Base64url without padding (RFC 4648 §5): the encoding of every key,
// nonce and ciphertext field the web client puts on the wire or on disk.

const BASE64URL_RE = /^[A-Za-z0-9_-]*$/;

export function encodeBase64Url(bytes) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = '';
  for (let i = 0; i < view.length; i += 1) binary += String.fromCharCode(view[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function decodeBase64Url(text) {
  if (typeof text !== 'string' || !BASE64URL_RE.test(text) || text.length % 4 === 1) {
    throw new TypeError('invalid base64url');
  }
  const padding = '='.repeat((4 - (text.length % 4)) % 4);
  const binary = atob(text.replace(/-/g, '+').replace(/_/g, '/') + padding);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out;
}
