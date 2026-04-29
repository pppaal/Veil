# Sealed sender — design

## Status

Design draft. **Not implemented**. External crypto review required before
merge.

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
