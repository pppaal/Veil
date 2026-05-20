// Canonical Additional Authenticated Data (AAD) builder for AES-GCM.
//
// F-1 from docs/internal-precheck-crypto-review.md: bind envelope
// context to the AEAD tag so the routing metadata can't be tampered
// without breaking decryption. The web demo already binds
// conversationId via the HKDF `info` parameter; this adds the sending
// device id so a ciphertext can't be re-attributed to a different
// device.
//
// CRITICAL invariant: encrypt and decrypt MUST call this with the same
// inputs to produce byte-identical output. We use a length-prefixed
// encoding so no field's content can be confused with a delimiter
// (a "canonicalization" defense — e.g. fields "ab"+"c" vs "a"+"bc"
// must not collide).

const VERSION_TAG = 'veil-aad-v1';

// Returns a Uint8Array suitable for the AES-GCM `additionalData` field.
// Layout: utf8(VERSION_TAG) then, per field, a 4-byte big-endian
// length prefix followed by the utf8 bytes of the value.
export function buildAad(fields) {
  const enc = new TextEncoder();
  const parts = [enc.encode(VERSION_TAG)];
  // Deterministic field order — changing this order is a wire break.
  const ordered = [
    fields.conversationId ?? '',
    fields.senderDeviceId ?? '',
    fields.recipientUserId ?? '',
  ];
  for (const value of ordered) {
    const bytes = enc.encode(String(value));
    const len = new Uint8Array(4);
    new DataView(len.buffer).setUint32(0, bytes.length, false); // big-endian
    parts.push(len, bytes);
  }
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}
