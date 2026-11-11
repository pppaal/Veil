# VEIL Threat Model Summary

## In scope

- server compromise attempting to read stored message data
- accidental plaintext leakage through logs, analytics, or push payloads
- unauthorized message access through hidden admin tooling
- account takeover attempts through password recovery or reset flows
- unsafe device transfer that bypasses possession of the old device

## Defensive product choices

- the server stores no plaintext message content: messages, reactions and
  stories are ciphertext, and display names, profile text, contact names and
  report notes are not stored at all. Group and channel names and
  descriptions and device labels are still stored in readable form (see the
  residual risks below); they are the only fields the schema privacy gate
  allowlists. Every stored field is annotated and CI regenerates the list of
  what a seized server reveals (`server-data-inventory.md`,
  `scripts/schema-privacy-check.mjs`)
- no password reset, no account recovery and no backup exist, sealed or not:
  losing every device loses the account (`no-recovery.md`). CI rejects
  recovery routes, modules, schema models and contract types
  (`scripts/policy-check.mjs`)
- a deleted account's handle is quarantined for 90 days (a peppered HMAC, not
  the handle, is kept), so a stranger cannot re-register it and inherit the
  trust its contacts gave the old owner
- device last-seen and last-sync times are stored as the UTC day only
- device transfer requires explicit action from the active old device
- push payloads are metadata-only (senderDeviceId excluded)
- no contact sync reduces unnecessary address-book exposure
- single active device model simplifies trust and revocation in v1
- rate limiting on auth, user lookup, key directory, message send, attachment ticket, and abuse report endpoints (global 60/min + per-route tightening)
- key material is served only to signed-in devices (`GET /v1/keys/:handle`); there is no anonymous key lookup
- Helmet security headers (CSP, HSTS, COEP) in production
- Swagger disabled by default in production
- bidirectional user blocks enforced at conversation creation, direct message send, and direct call initiation, with opaque "NotFound" / "unreachable" framing that hides block state from the blocked user
- per-conversation mutes suppress push wakes only — realtime + persistence stay consistent across devices
- abuse reports throttled to 6/min/user so the moderation queue can't be weaponized as DoS
- disappearing messages: per-conversation TTL + periodic global cron that hard-deletes expired rows even in idle conversations
- view-once messages: server hard-deletes the row on first non-sender read and broadcasts `message.consumed` for cache invalidation
- the 1:1 message AEAD binds the frame header / routing fields (sender ratchet public key, message counter, `senderDeviceId`) as associated data, so altering any of them invalidates the GCM tag (mobile adapter `lib-x25519-aes256gcm-v3`; see `crypto-envelope-spec.md` → "AEAD associated data (header binding)")

## Deliberate exclusions

- the production crypto adapter has not yet been externally audited
- multi-device concurrent session complexity is intentionally deferred
- public social surfaces and open discovery are intentionally absent
- private group messaging is supported; public groups are not

## Operational rules

- never log plaintext content
- never include plaintext in analytics or monitoring payloads
- never add server-side decryption endpoints
- never store private keys on the server
- rate limit public-facing endpoints
- validate all request DTOs

## Residual risks

- production crypto adapter (X25519+AES-256-GCM) is integrated but not yet externally audited
- the session opener bootstraps from the responder's static identity key, so the first message of a session lacks forward secrecy until the first ratchet step. The server-side X3DH one-time-prekey pool now exists (per-device upload/count + atomic single-use claim; `libsignal-migration-design.md` phase L.4), but the client is not yet wired to publish/consume prekeys, so this gap is closed on the server and pending on the client
- group conversations use a single shared key with no forward secrecy / post-compromise security / cryptographic member-revoke — server-side epoch bookkeeping and the opt-in flag have shipped (phases AB.1/AB.2), but the Sender-Key client crypto itself is still design-only (`group-sender-keys-design.md`)
- sender metadata and the conversation membership graph are visible to the server in plaintext; sealed sender is under revision because the current design does not hide the sender (`sealed-sender-design.md`)
- group and channel names and descriptions are still stored in plaintext until encrypted group metadata ships, and device labels until encrypted profiles ship (allowlisted in `scripts/schema-privacy-check.mjs`)
- the attachment presigned MinIO/S3 flow (server-side ticketing, strict 64-hex sha256 integrity validation, size caps, rate limits) is implemented; residual risk is that the object-storage deployment configuration (bucket policy, credential rotation) is environment-specific and the flow has not been externally pentested
- mobile local database encryption-at-rest is prepared conceptually but not finalized
- transport/session hardening still needs production infrastructure work
