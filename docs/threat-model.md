# VEIL Threat Model Summary

## In scope

- server compromise attempting to read stored message data
- accidental plaintext leakage through logs, analytics, or push payloads
- unauthorized message access through hidden admin tooling
- account takeover attempts through password recovery or reset flows
- unsafe device transfer that bypasses possession of the old device
- a stolen bearer token (access or refresh) used for an irreversible takeover
  or lockout

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
- device last-seen and last-sync times are stored as the UTC day only, and
  per-conversation sync and read cursors as conversation orders with no
  timestamp
- device transfer requires explicit action from the active old device: the
  approval is signed with the old device's auth key over the claim and the
  fingerprint the user compared, so a stolen bearer token alone cannot hand
  the account to other keys. Account deletion and revoking the calling or last
  device likewise need the device to sign a fresh challenge. Every relay
  requires these proofs, in development too (`device-transfer-flow.md`). They
  do not help against malware or same-origin
  script on the device itself, which can use its key
- push payloads are metadata-only (senderDeviceId excluded)
- no contact sync reduces unnecessary address-book exposure
- single active device model simplifies trust and revocation in v1
- rate limiting on auth, user lookup, key directory, message send, attachment ticket, and abuse report endpoints (global 60/min + per-route tightening); realtime events (typing, call signals) have their own per-device budget, which reconnecting does not reset, signals are relayed only for ringing or active calls and capped at 64 KiB, and a socket frame over 128 KiB closes the socket
- key material is served only to signed-in devices (`GET /v1/keys/:handle`, and `GET /v1/keys/group/:conversationId` to current group members); there is no anonymous key lookup
- Helmet security headers (CSP, HSTS, COEP) in production
- Swagger disabled by default in production
- bidirectional user blocks enforced at conversation creation, direct message send, and direct call initiation, with opaque "NotFound" / "unreachable" framing that hides block state from the blocked user; handle lookups (`GET /v1/users/:handle`, `GET /v1/keys/:handle`, the legacy prekey claim) answer a block in either direction exactly like an unknown handle and claim no prekey. An existing direct conversation still reveals a block through `peer_unreachable` on send
- per-conversation mutes suppress push wakes only — realtime + persistence stay consistent across devices
- abuse reports throttled to 6/min/user so the moderation queue can't be weaponized as DoS
- disappearing messages: per-conversation TTL + periodic global cron that hard-deletes expired rows even in idle conversations
- view-once messages: server hard-deletes the row on first non-sender read and broadcasts `message.consumed` for cache invalidation
- the 1:1 message AEAD binds, as associated data, every routing field the relay forwards in clear (envelope version, `conversationId`, `senderDeviceId`, `messageType`), the whole frame header (sender ratchet public key, previous-chain length, message counter and, on a PreKey frame, the X3DH header) and both parties' identity keys, so relabelling a frame or altering any of them invalidates the GCM tag; `expiresAt` is deliberately not bound, and the authenticated expiry travels in the encrypted payload (protocol v2, adapter `lib-x3dh-x25519-aes256gcm-v4`; see `crypto-envelope-spec.md` → "AEAD associated data (v4)"). Legacy v1 sessions, spoken only with peers that still publish v1 bundles, bind only the ratchet public key, the message counter and `senderDeviceId`

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
- 1:1 sessions (protocol v2) open with X3DH over signed and one-time prekeys, which the mobile client publishes and claims; when a target's one-time prekey pool is empty or a claim budget is spent, the session opens on the signed prekey alone, and that first message has no one-time-prekey forward secrecy and can be replayed once its stored state has aged out (`crypto-envelope-spec.md`). Sessions still on legacy v1 bundles keep the old static-key bootstrap
- groups created by current mobile clients use Sender Keys (`veil-group-v1`): per-sender chain keys that ratchet with every message and are replaced at every membership change, so a removed member cannot read later messages (`group-sender-keys-design.md`; not yet externally reviewed). Whether a group uses Sender Keys is not left to the server: a device pins the mode the first time a listing or an authenticated group frame shows it, and refuses pairwise frames there from then on, and the server refuses to turn the flag off (`sender_keys_irreversible`). Groups created by older clients stay on a single shared key with no forward secrecy, post-compromise security or cryptographic member removal, and a device that has never seen a group in Sender Keys mode trusts the server's listing for it. The web client does not take part in groups under protocol v2
- group membership is decided by the server. A malicious or compromised server can add a member (an account of its own) to a group; that member's devices then receive the group's keys and can read every message sent after the addition, though not earlier ones. Nothing in the protocol stops the addition: the mobile client shows a notice in the chat whenever the server's list adds or removes a member, and the members can be checked on the safety number screen. The web client does not take part in groups under protocol v2
- sender metadata and the conversation membership graph are visible to the server in plaintext; sealed sender is under revision because the current design does not hide the sender (`sealed-sender-design.md`)
- group and channel names and descriptions are still stored in plaintext until encrypted group metadata ships, and device labels until encrypted profiles ship (allowlisted in `scripts/schema-privacy-check.mjs`)
- the attachment presigned MinIO/S3 flow (server-side ticketing, strict 64-hex sha256 integrity validation, size caps, rate limits) is implemented; residual risk is that the object-storage deployment configuration (bucket policy, credential rotation) is environment-specific and the flow has not been externally pentested
- mobile local database encryption-at-rest is prepared conceptually but not finalized
- transport/session hardening still needs production infrastructure work
