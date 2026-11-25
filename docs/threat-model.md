# VEIL Threat Model Summary

## In scope

- server compromise attempting to read stored message data
- accidental plaintext leakage through logs, analytics, or push payloads
- unauthorized message access through hidden admin tooling
- account takeover attempts through password recovery or reset flows
- unsafe device transfer that bypasses possession of the old device
- a stolen bearer token (access or refresh) used for an irreversible takeover
  or lockout
- impersonation by a new or look-alike account: a stranger who writes as
  family on a new number, as a bank, a courier or the police, or under a
  handle close to a contact's (see the section below)

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

## Impersonation by a new or look-alike account

The threat: an account the user has never talked to writes first and
pretends to be someone they trust, most often "Hi mum, this is my new
number" followed by a request for money, a code or an app, or a handle one
character away from a saved contact's. The server cannot help: it sees no
text, and anyone with a handle can open a 1:1 or add the user to a group.

The mitigation runs on the phone and sends nothing: not the text it reads, a
result, a matched word, who an account is to the phone, or a link. The
privacy policy needed no change. The code is in
`apps/mobile/lib/src/core/safety/` (rules) and
`apps/mobile/lib/src/features/safety/application/contact_trust.dart`
(relationships and requests); `apps/mobile/README.md` explains each part.

- **Message requests.** A chat someone else starts waits as a request until
  the user accepts it, unless the phone already trusts everyone in it. Until
  then it sends no read receipt, typing indicator or reaction there and
  fetches no photo or file by itself, so a scammer cannot tell the message
  was read. The request bar offers Block and Report (Leave in a group).
- **Who each account is.** The phone ranks every account as changed,
  verified, saved, known or new from facts a stranger cannot create in
  minutes: a verified safety number, a nickname at least a week old, or a
  1:1 accepted at least a week before the message in which this phone had
  sent a text or file by then (a reply sent after the message does not
  count). In a group, a member also counts as known through that group
  when the user created it, when it was accepted at least a week before
  the message, or when it was listed at the first run, members added
  later included; otherwise only through the user's own 1:1 with them.
  In a 1:1 chat, an identity key check that read the directory before a
  newer "safety number changed" event can no longer clear that event
  (`identity_trust.dart`, `peer_session_resolver.dart`).
- **Warnings.** Fixed rules (not a model) put one line under a message that
  looks like a common scam, more readily from a new or changed account. A
  banner warns, until the account is verified, when a handle looks like a
  saved or verified contact's or when a new account says it is family.
- **Links and app files.** A tap opens a link at once only for the user's
  own message or a verified contact's, in an accepted chat, and only when
  the link looks ordinary; otherwise a sheet asks first, and app-file,
  hidden and look-alike links get the stronger sheet from anyone. An
  `.apk`, `.xapk` or `.apks` file asks before it opens or saves. The phone
  never fetches or expands a link.

Limits that stay in this version:

- a long con (weeks of small talk, then the ask) passes the week rule: by
  then the account counts as known, and money asks from a known account are
  flagged only with urgency, secrecy, a third party's account or an excuse
  not to call
- a handle the user typed in New chat, or saved in Contacts, because a
  scammer gave it outside Veil makes the chat one the user started: it is no
  request and gets no family-claim line or banner (the money, code, link and
  app-file warnings still apply)
- the first run after install, upgrade or a move to a new phone accepts
  every chat the server lists then, a stranger's waiting chat included: the
  phone trusts the server's listing once, and a chat holding a message the
  server labels as this account's counts as known at once
- rules can be dodged: text in a photo, new spellings, a whole message in
  English with a space between every letter. A message with no warning can
  still be a scam
- a few real company domains (for example epost.kr) can get the stronger
  link sheet
- a screenshot notice or a timer change made in a stranger's chat in the
  seconds before the first chat list loads can still go out; a reaction is
  refused then too
- the delivered tick still shows the sender that a request reached the
  phone: the server marks delivery when the phone fetches the message
- in a group with more than one other member there is no look-alike or
  family-claim banner
- in a group listed at the first run, or accepted a week or more ago,
  every member counts as known, one added to it later included: a scammer
  added to such a group gets a known sender's lines, not a stranger's
- the lock-screen notification for a request says only "Message request",
  but the Android beta has no push notifications, so this applies only
  where the app raises notifications
- if the phone cannot read its trust record after three retries, requests,
  risk lines and the family-claim banner are off until the next sign-in;
  look-alike checks against verified contacts and the link sheets still work

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
