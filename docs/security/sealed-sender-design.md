# Sealed-Sender Design (Draft)

Status: **design** — not yet implemented.
Owner: security.
Target commit window: post external crypto audit of existing adapter.

## Motivation

Today every message send is authenticated by the sender's JWT, and the server
therefore learns the sender's identity for every ciphertext it relays. For a
privacy messenger this is an avoidable metadata leak: the server should be
able to route a message to a recipient without learning who sent it, as long
as it can still bill rate limits, reject abuse, and expire idle sessions.

This document specifies a Signal-style sealed-sender scheme adapted to the
current Veil stack (X25519 + AES-256-GCM + Ed25519 identity keys). It is the
next protocol-level privacy win after the existing "ciphertext-only relay"
stance, and it is the last privacy frontier the server can deliver without
external dependencies (STUN/TURN, external audits, etc.).

## Scope

In scope:

- direct (1:1) messages and their receipts
- group messages (same delivery-cert scheme, per-recipient fan-out)

Out of scope (v1):

- key bundle fetch — still authenticated (or public) because it bootstraps
  first contact; blinding it requires an anonymous credential scheme
- presence/typing signals — low-entropy, short-lived, not worth the cost
- attachments — blob access is already gated by a short-lived presigned URL

## Components

### 1. Delivery certificates

On login (or device trust event), the server issues each device a
*delivery certificate*:

```
DeliveryCert = {
  deviceId: UUID,
  userId: UUID,
  issuedAt: int64,     // unix seconds
  expiresAt: int64,    // issuedAt + 24h
  deviceIdentityKey: X25519 public key (32 bytes)
}
Signature = Ed25519(serverIdentityKey, canonical(DeliveryCert))
```

The server signs with a long-lived `SERVER_SEALED_SENDER_SIGNING_KEY` (Ed25519),
rotated on the same cadence as the JWT signing key. The cert itself is given
to the sender over their authenticated channel and is stored on-device only.

### 2. Sealed envelope

When sending a sealed message, the sender builds the existing
`veil-envelope-v1` body (ciphertext + nonce + messageType + optional
`expiresAt`/`viewOnce`), and then wraps it:

```
SealedOuter = {
  version: "veil-sealed-v1",
  conversationId: UUID,               // clear (needed for fan-out)
  recipientUserId: UUID,               // clear (needed for routing)
  sealedBody: bytes                    // inner plaintext below, then HPKE-sealed to recipient
}

SealedInner (before HPKE seal) = {
  senderDeliveryCert: DeliveryCert,
  senderCertSignature: Signature,
  envelope: veil-envelope-v1 body
}
```

HPKE seal uses `DHKEM(X25519, HKDF-SHA256) + HKDF-SHA256 + AES-256-GCM`
(RFC 9180), keyed to the recipient's device identity public key fetched via
the existing key-bundle directory.

### 3. Unauthenticated delivery endpoint

A new endpoint accepts sealed messages without an `Authorization` header:

```
POST /v1/sealed/messages
Body: { conversationId, recipientUserId, sealedBody, clientMessageId }
```

The endpoint's rate limit is keyed on a sender-supplied *anonymous token*
(blinded server-issued token, scoped per-day, revocable). See the Abuse &
rate-limiting section below.

The server:

1. Checks `conversationId` exists and has `recipientUserId` as a member.
   On failure returns `NotFound` (uniform error prevents enumeration).
2. Charges rate limit against the anonymous token.
3. Persists `(conversationId, recipientUserId, sealedBody, clientMessageId,
   serverReceivedAt)` — crucially no sender identity.
4. Broadcasts `message.new.sealed` over realtime with the same fields.

### 4. Recipient-side unwrap

On receipt:

1. Recipient decrypts `sealedBody` with its X25519 device key.
2. Verifies `senderCertSignature` against the server's published signing key.
3. Verifies `DeliveryCert.expiresAt > now` and `DeliveryCert.userId` matches
   the conversation-member set (server can publish membership in the clear).
4. Feeds the unwrapped `envelope` into the existing decrypt pipeline as if
   it had come through the authenticated path.

Receipt events (`delivered`, `read`) reverse the same path: the recipient
issues sealed receipts under its own delivery cert. Out-of-order delivery is
fine because receipts are keyed by `messageId`.

## Abuse & rate-limiting

Sealed sending cannot bill `JwtAuthGuard` throttles. Two options:

**A. Privacy Pass / anonymous credentials.** Server issues daily blind
tokens to each authenticated device (N tokens/day, signed via
publicly-verifiable VOPRF). Each sealed send spends one token. The server
can't link tokens back to issuance, but the total daily budget caps abuse.

**B. Receiver-aggregated rate limit.** Server counts sealed deliveries *per
recipient*, not per sender. Abusive sending is visible as "this recipient is
being flooded", and the recipient can mute/block with existing safety
surfaces. Simpler, but opens the door to reputation-poisoning attacks.

Recommendation: **A** for the first cut, because it preserves unlinkability
even against a server that correlates traffic patterns.

## Migration

The existing authenticated send path stays in place and is the default
during the transition. Client behavior:

1. After a successful login, client fetches a delivery cert + daily
   anonymous-token bundle.
2. Client writes the cert to secure storage with a 24h TTL.
3. When composing a send, the client prefers the sealed path if
   (a) a valid cert is available, (b) a token is available, and (c) the
   recipient bundle advertises `supportsSealedSender: true`.
4. Falls back to the authenticated path otherwise.

Server behavior:

1. Flip `supportsSealedSender: true` on key-bundle responses only after the
   server has been upgraded with the new endpoint.
2. After 30 days of overlap, gate the authenticated send path on an env
   flag so it can be retired.

## Open questions

- **Cert revocation**: if a device key rotates, outstanding certs still
  look valid until `expiresAt`. Mitigation: keep cert TTL short (24h) and
  publish a revocation list at `/v1/sealed/revoked-certs` that clients fetch
  once per launch.
- **Clock skew**: `issuedAt` / `expiresAt` rely on server clock. Include
  a ±5 min skew allowance; reject anything outside a one-week absolute
  window regardless.
- **Replay**: `clientMessageId` is already unique per sender-device; in the
  sealed path the server can't dedup by sender. Use `messageId = hash(
  recipientUserId || clientMessageId || ciphertext)` as the primary key,
  which is deterministic under replay and therefore idempotent without
  revealing the sender.
- **Group fan-out**: sealed sends are per-recipient, so a group of N costs
  N sealed requests. Acceptable for v1; a future MLS-grade group can share
  one sealed envelope across members.

## Testing checklist

- [ ] sealed send round-trips through a test harness that never sees the
      sender identity at the server layer
- [ ] forged cert (wrong signature) is rejected on the recipient side
- [ ] expired cert is rejected on the recipient side
- [ ] anonymous token double-spend is rejected by the server
- [ ] sealed and authenticated sends interleave correctly in the same
      conversation without duplicate `messageId`s
- [ ] block/mute/report paths still function over sealed delivery
      (block enforcement moves to the recipient: recipient drops sealed
      messages whose decrypted `senderDeliveryCert.userId` is blocked)

## Non-goals

This design does not attempt to hide:

- that *some* device of the sender's account sent *something* at a given
  time — the issuing TLS session is still observable by the server
- presence, typing, or metadata beyond the message body
- recipient identity from the server (routing needs it)

These are hidden only under a mixnet-style architecture, which is out of
scope for Veil v1.
