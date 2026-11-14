export const DEV_ENVELOPE_VERSION = 'veil-envelope-v1-dev';
export const PROD_ENVELOPE_VERSION = 'veil-envelope-v1';
// Protocol v2 1:1 envelope (authenticated handshake + spec Double Ratchet).
// Its AAD excludes the outer expiresAt; the authenticated expiry rides in the
// inner payload, so the relay may clamp the outer value.
export const PROD_ENVELOPE_VERSION_V2 = 'veil-envelope-v2';
// Group Sender Keys envelope (mobile, phase AB.3). One ciphertext per send,
// fanned out unchanged to every member; the server only sees opaque bytes.
export const GROUP_ENVELOPE_VERSION = 'veil-group-v1';
// libsignal-backed 1:1 envelope (mobile bridge adapter). The ciphertext is a
// serialized libsignal CiphertextMessage; the server treats it as opaque.
export const LIBSIGNAL_ENVELOPE_VERSION = 'libsignal-v1';
export const SUPPORTED_ENVELOPE_VERSIONS = [
  DEV_ENVELOPE_VERSION,
  PROD_ENVELOPE_VERSION,
  PROD_ENVELOPE_VERSION_V2,
  GROUP_ENVELOPE_VERSION,
  LIBSIGNAL_ENVELOPE_VERSION,
] as const;
// Which envelope versions a conversation may carry. Pairwise (direct-family)
// envelopes are also what legacy shared-key groups and channels use; only a
// group that opted into Sender Keys switches to the group family, and then
// exclusively, so a sender cannot downgrade it back to a pairwise format.
export const ENVELOPE_VERSION_FAMILY: Readonly<Record<'direct' | 'group', readonly string[]>> =
  Object.freeze({
    direct: Object.freeze([
      PROD_ENVELOPE_VERSION,
      DEV_ENVELOPE_VERSION,
      PROD_ENVELOPE_VERSION_V2,
      LIBSIGNAL_ENVELOPE_VERSION,
    ]),
    group: Object.freeze([GROUP_ENVELOPE_VERSION]),
  });
export const DEV_ATTACHMENT_WRAP_ALGORITHM_HINT = 'dev-wrap';
export const PROD_ATTACHMENT_WRAP_ALGORITHM_HINT = 'x25519-aes256gcm';
// Development-only crypto markers. A production relay refuses them so a
// debug build can never put mock-encrypted traffic on a real deployment.
export const PRODUCTION_FORBIDDEN_ENVELOPE_VERSIONS: readonly string[] = Object.freeze([
  DEV_ENVELOPE_VERSION,
]);
export const PRODUCTION_FORBIDDEN_ATTACHMENT_HINTS: readonly string[] = Object.freeze([
  DEV_ATTACHMENT_WRAP_ALGORITHM_HINT,
]);
// Hard cap on group size, owner included. Sender Keys fan-out and the
// per-member key distribution cost grow linearly with membership.
export const GROUP_MAX_MEMBERS = 25;
// Upper bound (characters) for a device's base64url `signedPrekeyBundle`.
// The X25519-only bundle is ~200 chars; a libsignal bundle with a Kyber-1024
// prekey + signatures is ~2.5 KiB. 8 KiB leaves headroom without letting the
// directory be used as blob storage.
export const MAX_SIGNED_PREKEY_BUNDLE_LENGTH = 8192;
