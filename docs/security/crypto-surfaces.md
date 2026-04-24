# Crypto Surfaces — Audit-Ready Catalog

This is the external-audit reference: every place where Veil performs a
cryptographic operation, what algorithm is used, where the key lives, and
how urgent audit coverage is.

It is maintained alongside `crypto-adapter-architecture.md` and
`forward-secrecy-ratchet-design.md` — read those first for the *why*; this
doc is the *where*.

## Severity key

- **P0** — a flaw here breaks the end-to-end encryption guarantee.
- **P1** — a flaw here breaks authentication, session integrity, or
  forward secrecy.
- **P2** — a flaw here leaks metadata or degrades defense-in-depth without
  breaking E2EE.
- **P3** — defense-in-depth only; no confidentiality impact on its own.

## Surface inventory

### P0 — message body E2EE

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart` — `encryptMessage` | X25519 ECDH → HKDF-SHA256 → AES-256-GCM | per-message ephemeral X25519 + recipient identity X25519 | production adapter, behind `CryptoEngine` seam |
| `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart` — `decryptMessage` | inverse of above | recipient device identity X25519 private key | reads from secure storage |
| `apps/mobile/lib/src/features/.../ratchet` — DH ratchet chain advance | X25519 ratchet + HKDF chain key | per-session chain + message key | forward secrecy; see `forward-secrecy-ratchet-design.md` |
| `apps/mobile/lib/src/core/crypto/session_state_migration.dart` | snapshot serialization of ratchet state | session chain keys | audit must verify snapshots are only read by the owning device |

### P0 — attachment E2EE

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| attachment wrap (mobile, see `docs/attachment-flow.md`) | AES-256-GCM | random per-attachment content key, wrapped with recipient identity key | content key never touches the server |
| attachment unwrap (mobile) | inverse | | server returns only presigned URLs |

### P1 — authentication

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/auth/auth.service.ts` — challenge/verify | Ed25519 signature verify | device's published `authPublicKey` | challenge is server-generated, bound to deviceId |
| `apps/api/src/common/guards/jwt-auth.guard.ts` | HS256 JWT | `JWT_SECRET` (env) | rotation runbook in `docs/ops/jwt-secret-rotation.md` |
| `apps/api/src/modules/device-transfer/device-transfer.service.ts` | Ed25519 signature verify over transfer token | old device auth key | old-device-required posture |

### P1 — identity keys & prekey bundles

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| mobile — key bundle generation | X25519 identity + Ed25519 auth + signed prekey | device-local | never leaves device |
| API — `/users/:handle/key-bundle` | returns public halves only | — | public endpoint, rate limited; audit must confirm no private key ever reaches it |
| `apps/mobile/test/prekey_bundle_signature_test.dart` | Ed25519 verify over signed prekey | device's auth key | signed prekeys include auth signature so recipient verifies origin |

### P1 — backup

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/backup/backup_envelope.dart` — `seal` | PBKDF2-SHA256 (600k) → AES-256-GCM | passphrase-derived | per-seal salt + nonce; empty passphrase rejected |
| `apps/mobile/lib/src/core/backup/backup_envelope.dart` — `open` | inverse | passphrase | wrong passphrase → `SecretBoxAuthenticationError`, never silently succeeds |

### P2 — safety surfaces

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/safety/safety.service.ts` — `isBlockedEitherWay` | none (DB lookup) | — | audit target: make sure block check is executed BEFORE persisting or broadcasting any ciphertext |
| abuse report throttle — `@Throttle(6/min)` on `POST /safety/reports` | none | — | audit target: verify throttler key is userId, not IP |

### P2 — push

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/api/src/modules/push/push.service.ts` | APNs token-auth (ES256 JWT to APNs) / FCM OAuth2 | APNs `.p8` / FCM service account | `docs/apple-firebase-credential-setup-checklist.md` |
| push payload shape | metadata-only wake (no sender, no body, no conversationId) | — | `docs/push-privacy-review-checklist.md` is the normative spec |

### P2 — local storage

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| `apps/mobile/lib/src/core/security/local_data_cipher.dart` | AES-256-GCM | per-install key in `flutter_secure_storage` | Drift rows that hold sensitive fields are wrapped on write/read |
| `flutter_secure_storage` | OS keychain (iOS) / EncryptedSharedPreferences (Android) | hardware-backed where available | audit must verify key is not exported via debugger or backup service |

### P3 — transport

| Call site | Algorithm | Key material | Notes |
|-----------|-----------|--------------|-------|
| HTTPS to API | TLS 1.2+ (deployment) | server cert | Helmet + HSTS in production |
| WebSocket to `/v1/realtime` | WSS | same | `docs/observability-hygiene.md` — tokens passed via auth handshake, never query string in production |

## Audit asks

1. Walk the ratchet implementation end-to-end and confirm:
   - per-message keys are derived via HKDF-SHA256 with distinct info labels
     for root / chain / message key
   - ratchet advance happens on every sent message, not per batch
   - a compromised chain key does not recover prior message keys (forward
     secrecy test vector in `apps/mobile/test/forward_secrecy_test.dart`)

2. Review the prekey bundle signature flow and confirm:
   - signed prekeys are verified against the device's `authPublicKey`
     before the client treats them as trusted
   - first-contact attack surface is limited to a first-use-verified
     safety-number comparison

3. Review the backup envelope and confirm:
   - PBKDF2 iteration count is recent (OWASP 2023 → 600k for SHA-256)
   - no timing side-channel in `open()` (ArgumentError branches are fine;
     we rely on AES-GCM auth tag for constant-time failure)

4. Review the auth challenge flow and confirm:
   - challenges expire within `AUTH_CHALLENGE_TTL_SECONDS` (120s default)
   - challenge IDs are never reusable
   - replaying a signature with a mismatched deviceId is rejected before
     session issuance

5. Review attachment key wrap and confirm:
   - the per-attachment content key is generated with OS entropy and
     never persisted unwrapped on the server
   - download tickets expire within 10 min and cannot be re-minted for
     attachments the requester didn't send or receive

## Out of scope for v1 audit

These exist or are shipping but aren't yet worth a deep audit pass:

- group fan-out (no MLS yet; simple per-recipient encryption)
- stories / calls (scaffolds, no production crypto ownership)
- channel broadcast (not yet shipped)

The packet in `external-security-review-packet.md` lists the docs and
artifacts to send to the auditor; this catalog is the in-depth companion
that tells them *where to look*.
