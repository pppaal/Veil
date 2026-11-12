# Crypto Surfaces — Audit-Ready Catalog

This is the external-audit reference: every place where Veil performs a
cryptographic operation, what algorithm is used, where the key lives, and
how urgent audit coverage is. It lists call sites; the wire format, labels
and constants are specified in `crypto-envelope-spec.md`, which is normative
for protocol v2 (`veil-envelope-v2`) on both clients, and pinned byte for
byte by `packages/shared/test-vectors/crypto-kat.json`.

Two clients implement protocol v2: mobile (Dart, `apps/mobile/lib/src/core/crypto/`)
and web (WebCrypto, `apps/web-demo/src/crypto/`). An independent node:crypto
implementation, `scripts/crypto-test-vectors.mjs`, generates and checks the
vectors; `apps/mobile/test/crypto/crypto_kat_v2_test.dart` and
`apps/web-demo/__tests__/kat-v2.test.js` reproduce them, and
`apps/mobile/test/interop/web_mobile_interop_test.dart` runs a session between
the two implementations.

There is no backup and no account recovery, so there is no backup or
recovery cryptography to review (`no-recovery.md`; `scripts/policy-check.mjs`
fails CI if one appears).

## Severity key

- **P0** — a flaw here breaks the end-to-end encryption guarantee.
- **P1** — a flaw here breaks authentication, session integrity, identity
  trust or forward secrecy.
- **P2** — a flaw here leaks metadata or degrades defense-in-depth without
  breaking E2EE.
- **P3** — defense-in-depth only; no confidentiality impact on its own.

## Surface inventory

### P0 — 1:1 message E2EE (protocol v2)

| Call site (mobile / web) | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/crypto/x3dh/x3dh_handshake.dart` / `apps/web-demo/src/crypto/x3dh.js` | X3DH: X25519 DH1..DH4 → HKDF-SHA256 (`veil-x3dh-v2`) | initiator IKx + ephemeral key; responder IKx, signed prekey, one-time prekey | mutual authentication: DH1 needs the initiator's IKx private key; the PreKey header carries IKed, IKx and `ikxSig` |
| `apps/mobile/lib/src/core/crypto/ratchet/double_ratchet.dart`, `ratchet/kdf.dart` / `apps/web-demo/src/crypto/ratchet.js`, `kdf.js` | Double Ratchet: X25519 DH steps, HKDF-SHA256 root and chain KDFs | per-session root, chain and message keys | PN in every header; at most 200 keys stashed per frame, 1000 per session, 7-day lifetime |
| `apps/mobile/lib/src/core/crypto/ratchet/session_cipher.dart`, `ratchet/aead.dart`, `ratchet/frame_codec.dart` / `apps/web-demo/src/crypto/session-cipher.js`, `frame.js` | AES-256-GCM, AAD `veil-frame-aad-v4` over the routing fields | message key | seals and opens frames; installs sessions (glare, replay, archived states) only after the AEAD verifies |
| `apps/mobile/lib/src/core/crypto/payload/inner_payload.dart`, `message_padding.dart` / `apps/web-demo/src/crypto/payload-v2.js`, `padding.js` | inner payload and length padding inside the GCM plaintext | — | the body, attachment pointer and reply/edit references never leave the ratchet |
| `apps/mobile/lib/src/core/crypto/ratchet/session_record.dart`, `ratchet/session_store.dart` / `apps/web-demo/src/crypto/session-record.js`, `session-repo.js` | ratchet state persistence (snapshot schema 4) | session chain keys | mobile: secure storage; web: sealed under the identity's non-extractable `sessionKek` |
| `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart` | adapter behind the `CryptoEngine` seam | — | routes v2 and legacy v1 sessions; v1 content is reported `legacyUnauthenticated` |
| `apps/mobile/lib/src/core/crypto/ratchet/legacy_session.dart` / `apps/web-demo/src/crypto/legacy-v1dev.js` | legacy v1 (mobile, initiator only) and the retired web `v1-dev` format (read-only) | static-key bootstrap | no mutual authentication; kept so old history stays readable |

### P0 — attachments

| Call site (mobile / web) | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/crypto/attachment/attachment_cipher_v2.dart` / `apps/web-demo/src/crypto/attachment-v2.js` | AES-256-GCM per blob, AAD `veil-att-v2` ‖ attachmentId, Padmé padding, SHA-256 digest | random 32-byte key and 12-byte nonce per blob | the key, digest, size and type travel only inside the ratchet payload; the relay sees the opaque attachment id, ciphertext size and digest |
| `apps/mobile/lib/src/core/crypto/attachment/legacy_attachment.dart` | X25519 + HKDF wrap of a content key (`veil-attachment-wrap-v1`) | recipient static identity key | read-only, for attachments received before the pointer model |

### P0 — groups (Sender Keys, mobile)

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/crypto/group_sender_keys.dart` | per-sender HKDF-SHA256 chain → AES-256-GCM; per-epoch Ed25519 signature over AD ‖ nonce ‖ ciphertext | per-member chain key and per-epoch signing key | `veil-group-v1`; full re-key at every membership change (`group-sender-keys-design.md`) |
| `apps/mobile/lib/src/core/crypto/group_sender_keys.dart` (`seal`) driven by `apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart` | sealed chain-key distribution to each member device (ephemeral X25519 → HKDF-SHA256 → AES-256-GCM, signed by the sender's Ed25519 identity key) | recipient's signed prekey, verified against its identity key first | the coordinator decides which member devices get a key, through the identity-trust gate; the relay stores the sealed blob for 30 minutes (`apps/api/src/modules/groups`) and cannot open it |

The web client does not take part in groups under protocol v2. Groups
created by older clients stay on a single shared conversation key, with no
forward secrecy or cryptographic member removal.

### P1 — identity keys, prekeys and the directory

| Call site (mobile / web / relay) | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/crypto/x3dh/identity_keys.dart`, `x3dh/local_keyring.dart` / `apps/web-demo/src/crypto/identity.js`, `prekeys.js`, `bundle.js` | Ed25519 IKed signs IKx (`veil-ikx-v2`) and signed prekeys (`veil-spk-v2`); a separate Ed25519 auth key signs only challenges and transfer proofs | device-local; web private keys are non-extractable | superseded signed prekeys answer for 14 days; one-time prekeys are deleted after use |
| `apps/mobile/lib/src/features/conversations/data/messenger/prekey_maintenance.dart` | signed-prekey rotation and one-time prekey top-up | device-local | publishes public halves only |
| `apps/api/src/modules/prekeys/signed-prekey-bundle.ts`, `keys.service.ts` (`PUT /v1/keys/signed-prekey`) | Ed25519 verification of `ikxSig` and `spkSig` | the device's published identity key | a rotated bundle whose signatures do not verify is refused (`invalid_device_signature`); bundles sent at registration and transfer are stored as given, so the clients' own verification before use is what protects them; the relay never holds a private key |
| `apps/api/src/modules/prekeys` (`GET /v1/keys/:handle`, `GET /v1/keys/group/:conversationId`, one-time prekey claim) | none (directory) | public keys only | signed-in devices only; each one-time prekey is handed out once |

### P1 — identity trust (TOFU)

| Call site (mobile / web) | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/features/conversations/data/messenger/identity_trust.dart`, `peer_session_resolver.dart`, `conversation_crypto_router.dart` / `apps/web-demo/src/crypto/pins.js`, `apps/web-demo/src/domain/peer-bindings.js` | pin comparison of Ed25519 identity keys per (user, device) | pinned public keys | the gate every session bootstrap, inbound PreKey frame and sealed or opened frame passes; a changed key is never accepted automatically |
| `apps/mobile/lib/src/features/security/domain/safety_numbers.dart` / `apps/web-demo/src/crypto/safety-number.js` | SHA-512 iterated 5200 times (Signal NumericFingerprint), safety numbers v2 | pinned identity keys and user ids | pinned by `packages/shared/test-vectors/safety-number-v2.json` (`scripts/safety-number-vectors.mjs`) |

### P1 — authentication and step-up

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/auth/auth.service.ts` — challenge/verify | Ed25519 signature verify | device's published `authPublicKey` | challenge is server-generated, single-use, bound to the device |
| `apps/api/src/modules/auth/auth.service.ts` — `verifyDeviceStepUp` | Ed25519 over `<purpose>:<challengeId>:<challenge>` | device auth key | required on every relay for account deletion and revoking the calling or last device |
| `apps/api/src/modules/device-transfer/device-transfer.service.ts` | Ed25519 over `transfer-claim:…`, `transfer-approve:…:<fingerprint>`, `transfer-complete:…` | new device's auth key (claim, complete); old device's auth key (approve) | the approval binds the SHA-256 fingerprint of both new keys the user compared |
| `apps/api/src/common/guards/jwt-auth.guard.ts` | HS256 JWT | `VEIL_JWT_SECRET` | rotation runbook in `docs/ops/jwt-secret-rotation.md` |
| `apps/api/src/modules/auth/auth.service.ts` — refresh | SHA-256 of the refresh token | — | only the hash is stored (`metadata-retention.md`) |

### P2 — local storage

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/security/local_data_cipher.dart` | AES-256-GCM | per-install key in `flutter_secure_storage` | wraps sensitive fields of the local cache |
| `apps/mobile/lib/src/core/storage/secure_storage_service.dart` | OS keychain (iOS) / EncryptedSharedPreferences (Android) | hardware-backed where available | holds identity, prekey and session material |
| `apps/web-demo/src/platform/content-store.js` | AES-256-GCM, AAD `message-contents` ‖ id | one non-extractable key per conversation | decrypted contents, decrypted once; deleting a conversation's key crypto-shreds its records |
| `apps/web-demo/src/platform/session-store.js`, `apps/web-demo/src/platform/wipe.js` | IndexedDB storage of non-extractable CryptoKeys | device-local | the wipe retires the handle for good (no recovery) |

### P2 — relay-side hashing

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/handles/retired-handles.service.ts` | HMAC-SHA256 of a deleted handle | `VEIL_RETIRED_HANDLE_PEPPER` | 90-day quarantine without storing the handle |
| `apps/api/src/common/throttler/redis-throttler.storage.ts` | unkeyed SHA-256 of route and client (`ip:` or `dev:`) | — | reversible for IPv4 by brute force; kept at most about two minutes (`metadata-retention.md`) |

### P2 — push

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/push/push.service.ts` | APNs token-auth (ES256 JWT) / FCM OAuth2 | APNs `.p8` / FCM service account | `docs/apple-firebase-credential-setup-checklist.md` |
| push payload shape | metadata-only wake (no sender, no body, no conversation id) | — | `docs/push-privacy-review-checklist.md` is the normative spec |

### P3 — transport and one-time links

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| HTTPS / WSS to the relay | TLS 1.2+ (deployment); mobile pins (`VEIL_TLS_PINS`) | server certificate | Helmet + HSTS in production |
| `apps/web-demo/src/crypto/secret-link.js` | AES-256-GCM; key = HKDF-SHA256 of a 256-bit fragment key, optionally mixed with PBKDF2-SHA256 (600000) of a passphrase | fragment key never reaches the server | one-time links (`feature-one-time-link.md`); the relay stores ciphertext and salt only |

### Not built by default

`apps/mobile/lib/src/core/crypto/libsignal_bridge_adapter.dart` and the
Kotlin/Swift handlers are an opt-in libsignal path; default builds leave the
native bridge out and it has never been built into an app
(`libsignal-migration-implementation.md`). It is not part of this audit
unless the build under review opts in.

## Audit asks

1. Protocol v2 against `crypto-envelope-spec.md`, on both clients:
   - X3DH authenticates both parties (DH1), `ikxSig` and `spkSig` are
     verified before a bundle is used, and a one-time prekey is consumed
     once and only after the session is persisted
   - the Double Ratchet derives per-message keys with distinct labels,
     bounds skipped keys, rejects replays and gives post-compromise security
     on the next DH step
   - mobile and web produce identical bytes for `crypto-kat.json`
2. Identity trust: every path that installs, opens or seals a session goes
   through the pin check first, a changed identity is never accepted without
   the user, and the safety number is computed from the pinned key.
3. Sender Keys (mobile): chain keys and signing keys are replaced at every
   membership change, a removed member holds nothing that opens later
   messages, and the distribution blob is bound to group, epoch, sender and
   recipient. Group membership itself is decided by the server
   (`threat-model.md`).
4. Attachments: the per-blob key comes from OS entropy, never reaches the
   relay, and the digest is checked in constant time before decryption.
5. Authentication and step-up: challenges expire within
   `VEIL_AUTH_CHALLENGE_TTL_SECONDS` (120 s by default) and are single-use;
   step-up and transfer proofs are bound to their purpose and cannot be
   replayed across purposes or devices.
6. Local storage: the web client's keys stay non-extractable, and the mobile
   local cache wraps every sensitive field.

## Out of scope for v1 audit

These exist or are shipping but aren't yet worth a deep audit pass:

- stories and calls (scaffolds, no production crypto ownership)
- channel broadcast (not yet shipped)
- the opt-in libsignal bridge (see above)

The packet in `external-security-review-packet.md` lists the docs and
artifacts to send to the auditor; this catalog is the in-depth companion
that tells them *where to look*.
