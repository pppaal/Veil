# Sealed sender — design

## Status

**Under revision: the current design does not hide the sender.** Not
implemented. Nothing in this document describes current behaviour, and no
VEIL material may claim sealed sender until a revised design ships and has
been externally reviewed.

This document merges the two earlier drafts (this file and the former
`docs/security/sealed-sender-design.md`). Both had the same flaw, recorded
below so the revision starts from it.

## Why the current design does not hide the sender

The drafts post "sealed" messages through the existing authenticated path,
or keep that path for rate limiting. In VEIL that reveals the sender anyway:

1. The bearer token identifies the posting device on every authenticated
   request (`JwtAuthGuard`), so a send through `POST /v1/messages` with a
   zero `senderDeviceId` still tells the server which device sent it.
2. A direct conversation's member rows and `conversations.direct_key` (the
   two sorted user ids) name both parties, so a visible `conversationId`
   gives the pair away.
3. Receipts, typing indicators and edit/delete events are server-side events
   keyed by user and device, so the recipient's read receipt reveals who
   sent what to whom.
4. `messages.sender_device_id` is a required foreign key with
   `onDelete: Restrict`, so a zero UUID cannot even be inserted, and the
   `(sender_device_id, client_message_id)` idempotency key would put every
   sealed sender into one shared namespace.
5. The sender certificate in the first draft carries no sender identity key
   and no proof of possession, so any recipient of Alice's messages could
   replay her certificate to others.

## What a revision needs (from the security review)

- An unauthenticated per-device delivery endpoint with no JWT, no logging of
  identifiers and no IP retention, authorized by an unidentified-access key
  derived from an encrypted profile key and stored only as a verifier.
- A mailbox table with no sender or conversation columns.
- A sender certificate that binds sender user, device and identity key,
  signed by a dedicated key separate from the JWT secret, which recipients
  check against their pinned identity for that sender.
- Receipts, typing and edit/delete moved into end-to-end encrypted control
  messages (reactions already are), so they stop revealing the pair.
- Per-recipient rate limits instead of per-sender ones.

The rest of this document is the earlier draft, kept as input to the
revision.

## Problem statement

VEIL today encrypts message bodies end-to-end. The server learns:

- who sent each message (`senderDeviceId`)
- who received it (`recipientUserId` for 1:1; full member list for groups)
- when (`serverReceivedAt`)
- approximate size (`ciphertext` length)
- conversation graph (which user-ids talk to which)

The first two are the strongest piece of metadata an attacker can grab
in a server compromise: who-talks-to-whom can be enough to identify a
journalist's source even with no body content. Signal's "Sealed Sender"
mitigates by hiding the sender from the server. We adopt the pattern.

## Goals

1. Server cannot identify the sender of an inbound message body.
2. Recipient still verifies sender identity end-to-end.
3. Spam and abuse paths still work (rate limiting on the *recipient*
   instead of sender, plus optional sender-cert challenge for unknown
   senders).
4. Group sends not in scope here (groups have inherent member-list
   visibility — see group-sender-keys-design.md for the parallel work).

## Non-goals

- Hiding the **recipient** from the server. The recipient is needed
  for fanout — a fully metadata-blind delivery would require Pond /
  mixnet style protocol and is not v1.
- Hiding **timing** correlation. Server can still observe when
  packets arrive at user X.
- Hiding **packet size**. We do not pad to fixed sizes in v1.

## Design overview (Signal-style)

A **sender certificate** is a server-issued, time-limited credential
that the sender attaches inside the encrypted envelope. The server
sees only:

```
{
  conversationId,           // visible — server uses for fanout
  recipientUserId,          // visible — server uses for fanout
  ciphertext,               // includes the sealed sender envelope
  nonce,
}
```

`ciphertext` itself decomposes (after E2E decrypt by recipient) into:

```
sealedEnvelope = senderCertificate || senderEphemeralPub || aeadCiphertext || aeadTag
```

Key derivation routes through the existing X25519 ECDH between
`senderEphemeralPriv` and `recipientIdentityPub`, so the sender does
not need to know the recipient's ratchet state.

## Sender certificate

```
SenderCertificate = {
  senderUserId: UUID,
  senderDeviceId: UUID,
  senderHandle: string,
  expiresAt: timestamp,
  serverPubKey: Ed25519 pub used to sign,
  serverSignature: Ed25519(over senderUserId|senderDeviceId|senderHandle|expiresAt)
}
```

Server issues a fresh certificate on `POST /v1/auth/sealed-cert` for
authenticated devices. Clients cache and renew before `expiresAt`
(default 7 days). Recipients verify `serverSignature` against a
well-known server pubkey (rotated quarterly, same distribution channel
as the TLS pin).

## Send flow

```
1. Sender:
   a. fetch fresh certificate if cache expiring
   b. compute (senderEphemeralPriv, senderEphemeralPub) for this msg
   c. compute shared = X25519(senderEphemeralPriv, recipientIdentityPub)
   d. derive aeadKey = HKDF(shared, salt=conversationId, info="sealed-v1")
   e. plaintext = (senderCert || originalEnvelopeBody)
   f. ciphertext = AES-256-GCM(aeadKey, nonce, plaintext, AD={conversationId,recipientUserId})
   g. sealedCiphertext = senderEphemeralPub || ciphertext
2. Sender posts /v1/messages with senderDeviceId="0..0" (zero UUID)
   and recipientUserId set normally. Server treats zero UUID as
   "anonymous send" and skips the existing senderDeviceId === auth.deviceId
   check, but rate-limits per (recipientUserId) instead of
   (senderDeviceId).
3. Recipient receives the envelope, runs:
   shared = X25519(recipientIdentityPriv, senderEphemeralPub)
   aeadKey = HKDF(shared, salt=conversationId, info="sealed-v1")
   plaintext = AES-256-GCM-Decrypt(aeadKey, nonce, ciphertext, AD)
   parse senderCert + body, verify cert signature.
4. Block check: recipient runs its local block list. If sender is
   blocked, drop silently — same UX as today's server-side block.
```

## Server changes

1. `senderDeviceId` validation: accept the all-zero UUID as a magic
   value that means "sealed". For sealed messages, skip the existing
   check that `envelope.senderDeviceId === auth.deviceId`. The auth
   token still authenticates the *posting* device for rate limiting.
2. Rate limiting: today's per-(senderDeviceId) limit no longer covers
   sealed sends because the device id is opaque. Add per-(actorDeviceId,
   recipientUserId) and per-(recipientUserId) limits. Recipient-side
   rate limiting catches the "stranger spamming user X" pattern.
3. `POST /v1/auth/sealed-cert`: issues a SenderCertificate signed by
   the server signing key. Body validation: device must be active,
   user.status='active'. Cert TTL = 7 days.
4. Server signing key: rotated quarterly. Public key published at
   `GET /v1/.well-known/sealed-sender-cert-keys` along with N+1
   future keys so clients can pre-warm.

## Threat model gains

| Adversary | Before | After |
|---|---|---|
| Server insider | sees A→B link in 1:1 | sees ?→B link |
| Server data leak | full conversation graph | recipient-only graph |
| Network observer (TLS broken) | A→server, server→B | same — sealed sender doesn't change network shape |
| Malicious A claiming to be C | rejected by recipient (sender cert verifies) | same |
| Spammer flooding B | per-sender rate limit | per-recipient rate limit (recipient's choice to throttle) |

## Threat model losses

1. Per-sender rate limiting becomes harder. A spammer that rotates
   ephemeral keys per send looks like many separate senders to the
   server. Mitigations: certificate-bound limits (one cert = N msg
   per minute), strict per-recipient ceilings, and an opt-in "only
   accept sealed sender from contacts" recipient setting.
2. Server cannot show "you have a new message from @alice" in push
   notifications without exposing the sender. We already do not put
   plaintext metadata in push payloads (policy-check enforces); push
   is just a "you have a message" wake. No regression.
3. Server cannot enforce "block @alice from messaging me" since it
   does not know the sender. Recipient enforces locally — works once
   the message is decrypted, costs the recipient one decrypt per
   blocked-sender envelope.

## Migration strategy

Phase AB.5 — sender cert issuance + accept
  - new endpoint /v1/auth/sealed-cert
  - new well-known endpoint for server signing pubkeys
  - server accepts envelopes with zero-UUID senderDeviceId
  - clients keep using normal sender id; server backward-compatible

Phase AB.6 — opt-in send
  - clients add a "sealed sender" toggle (default off in beta)
  - default on for messages between contacts after 30d soak
  - default on universally after 90d soak

Phase AB.7 — block-list semantics flip
  - server-side block now refuses *delivery* to a blocking recipient
    only for non-sealed messages; sealed messages get filtered
    client-side
  - documented in tester-guide-ko

## Test matrix

| # | Scenario | Expected |
|---|---|---|
| 1 | sealed send to mutual contact | recipient decrypts and verifies cert |
| 2 | sealed send with expired cert | recipient rejects, sender re-fetches cert and retries |
| 3 | sealed send to user who blocked sender | server delivers; recipient drops on local block check |
| 4 | sealed send with forged senderHandle (cert signature stripped) | recipient rejects on verify |
| 5 | spam: 100 sealed sends to one recipient from rotating ephemerals | recipient rate-limit fires |
| 6 | server replays a sealed envelope to a different recipient | AD mismatch, recipient rejects |
| 7 | rotated server signing key, old cert in flight | recipient verifies via cached old key, then renews |

## External review questions

1. Is the cert TTL of 7 days the right tradeoff vs server load
   (issuance) vs revocation responsiveness?
2. AD construction: should it include `senderEphemeralPub` to bind
   that field?
3. Can a malicious server modify the cert in transit? It is inside
   the AEAD-protected ciphertext, so no — confirm.
4. How does sealed sender interact with sender keys (groups)? Today
   we say "groups out of scope", but the sealed envelope could wrap
   a Sender Keys ciphertext if both are deployed.
5. Recipient-side block enforcement: what is the bandwidth cost of
   decrypting then dropping vs server-side drop?
6. Should the server ever know the sender, e.g. for moderation? We
   say no, but a cap on "abuse triage scope" should be documented.

## Cost estimate

| Phase | Effort | Risk |
|---|---|---|
| AB.5 cert issuance | 3d | low |
| AB.5 server accept | 2d | medium — auth path change |
| AB.6 client opt-in | 4d | medium — UX of "stranger sealed message" |
| AB.7 block-list flip | 2d | medium — docs + tester-guide updates |
| External review | 4-6w wall clock | external |

Total client-engineering: ~11 days. Wall-clock with audit:
~10-14 weeks.

## Decision required before AB.5 starts

1. Confirm cert TTL.
2. Confirm rate-limit policy (per-recipient ceiling values).
3. Confirm push notification flow stays "wake only" with no
   sender-derived metadata.
4. Confirm block-list semantics flip is acceptable to product.

## Appendix: the second draft (delivery certificates and anonymous tokens)

The former `docs/security/sealed-sender-design.md`, merged here unchanged
apart from heading levels. Its unauthenticated endpoint is closer to what a
revision needs, but it still keeps a sender-identifying cert inside a scheme
whose rate limiting and receipts were never reconciled with the points
above.

### Motivation

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

### Scope

In scope:

- direct (1:1) messages and their receipts
- group messages (same delivery-cert scheme, per-recipient fan-out)

Out of scope (v1):

- key bundle fetch — still authenticated (or public) because it bootstraps
  first contact; blinding it requires an anonymous credential scheme
- presence/typing signals — low-entropy, short-lived, not worth the cost
- attachments — blob access is already gated by a short-lived presigned URL

### Components

#### 1. Delivery certificates

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

#### 2. Sealed envelope

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

#### 3. Unauthenticated delivery endpoint

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

#### 4. Recipient-side unwrap

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

### Abuse & rate-limiting

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

### Migration

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

### Open questions

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

### Testing checklist

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

### Non-goals

This design does not attempt to hide:

- that *some* device of the sender's account sent *something* at a given
  time — the issuing TLS session is still observable by the server
- presence, typing, or metadata beyond the message body
- recipient identity from the server (routing needs it)

These are hidden only under a mixnet-style architecture, which is out of
scope for Veil v1.
