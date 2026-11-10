export const DEV_ENVELOPE_VERSION = 'veil-envelope-v1-dev';
export const PROD_ENVELOPE_VERSION = 'veil-envelope-v1';
// Group Sender Keys envelope (mobile, phase AB.3). One ciphertext per send,
// fanned out unchanged to every member; the server only sees opaque bytes.
export const GROUP_ENVELOPE_VERSION = 'veil-group-v1';
// libsignal-backed 1:1 envelope (mobile bridge adapter). The ciphertext is a
// serialized libsignal CiphertextMessage; the server treats it as opaque.
export const LIBSIGNAL_ENVELOPE_VERSION = 'libsignal-v1';
export const SUPPORTED_ENVELOPE_VERSIONS = [
  DEV_ENVELOPE_VERSION,
  PROD_ENVELOPE_VERSION,
  GROUP_ENVELOPE_VERSION,
  LIBSIGNAL_ENVELOPE_VERSION,
] as const;
export const DEV_ATTACHMENT_WRAP_ALGORITHM_HINT = 'dev-wrap';
export const PROD_ATTACHMENT_WRAP_ALGORITHM_HINT = 'x25519-aes256gcm';
// Upper bound (characters) for a device's base64url `signedPrekeyBundle`.
// The X25519-only bundle is ~200 chars; a libsignal bundle with a Kyber-1024
// prekey + signatures is ~2.5 KiB. 8 KiB leaves headroom without letting the
// directory be used as blob storage.
export const MAX_SIGNED_PREKEY_BUNDLE_LENGTH = 8192;
