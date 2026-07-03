# VEIL Threat Model Summary

## In scope

- server compromise attempting to read stored message data
- accidental plaintext leakage through logs, analytics, or push payloads
- unauthorized message access through hidden admin tooling
- account takeover attempts through password recovery or reset flows
- unsafe device transfer that bypasses possession of the old device

## Defensive product choices

- only encrypted envelopes are stored server-side
- no password reset exists; the only recovery path is a user-held,
  passphrase-sealed backup whose ciphertext the server stores but cannot
  decrypt (it holds neither the passphrase nor the derived key). The
  lost-device *retrieval* auth path for that backup is still an open design
  decision and is not yet built (`recovery-backup-design.md`)
- device transfer requires explicit action from the active old device
- push payloads are metadata-only (senderDeviceId excluded)
- no contact sync reduces unnecessary address-book exposure
- single active device model simplifies trust and revocation in v1
- rate limiting on auth, user lookup, key bundle, message send, attachment ticket, and abuse report endpoints (global 60/min + per-route tightening)
- Helmet security headers (CSP, HSTS, COEP) in production
- Swagger disabled by default in production
- bidirectional user blocks enforced at conversation creation, direct message send, and direct call initiation, with opaque "NotFound" / "unreachable" framing that hides block state from the blocked user
- per-conversation mutes suppress push wakes only — realtime + persistence stay consistent across devices
- abuse reports throttled to 6/min/user so the moderation queue can't be weaponized as DoS
- disappearing messages: per-conversation TTL + periodic global cron that hard-deletes expired rows even in idle conversations
- view-once messages: server hard-deletes the row on first non-sender read and broadcasts `message.consumed` for cache invalidation
- backup envelope uses PBKDF2-SHA256 600k + AES-256-GCM with per-seal salt + nonce; empty passphrase rejected; wrong passphrase fails authentication rather than returning garbage
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
- the recovery backup's security reduces to the user's passphrase strength: the server holds the sealed ciphertext, so a weak passphrase is offline-brute-forceable by anyone who obtains the blob. The lost-device retrieval auth (who may fetch the ciphertext, and whether a recovery code gates it) is an unresolved design decision (`recovery-backup-design.md`)
- sender metadata and the conversation membership graph are visible to the server in plaintext; sealed sender is design-only (`sealed-sender-design.md`)
- the attachment presigned MinIO/S3 flow (server-side ticketing, strict 64-hex sha256 integrity validation, size caps, rate limits) is implemented; residual risk is that the object-storage deployment configuration (bucket policy, credential rotation) is environment-specific and the flow has not been externally pentested
- mobile local database encryption-at-rest is prepared conceptually but not finalized
- transport/session hardening still needs production infrastructure work
