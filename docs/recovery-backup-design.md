# Encrypted recovery backup — design

## Status

**Storage substrate shipped. Lost-device retrieval auth: design-only,
decision required.** The server can now store and serve a user's
passphrase-sealed recovery envelope (authenticated, user-scoped). The
hard part — letting a user pull that envelope onto a *replacement* device
after losing the original — is deliberately **not** implemented yet because
it needs a security decision (below) and reconciliation with the threat
model's "no recovery channels" stance.

## Why

VEIL is single-active-device. Device transfer requires the **old** device to
approve (possession proof). That is the right default, but it has one failure
mode with no escape hatch today: **the old device is lost/destroyed.** Without
a recovery path the account — and every conversation key on it — is
unrecoverable. A passphrase-sealed backup gives the user (and only the user) a
way back, without weakening the server's zero-knowledge position.

## Invariants preserved

- The server stores **only** the opaque envelope. It never holds the
  passphrase or the derived key, so it **cannot decrypt** the backup. This
  keeps "never store *usable* private keys on the server" intact — the bytes
  at rest are useless without the user's passphrase.
- No server-side decryption endpoint is added.
- The envelope is the existing mobile `BackupEnvelope` primitive
  (`apps/mobile/lib/src/core/backup/backup_envelope.dart`):
  `veilbak:v1:<salt>:<nonce>:<ciphertext>:<mac>`, PBKDF2-SHA256 600k +
  AES-256-GCM. Empty passphrase rejected; wrong passphrase fails
  authentication rather than returning garbage.

## What shipped (storage substrate)

`recovery_blobs` table — one row per user (PK = `user_id`), holding the
opaque `ciphertext` + a `format` marker + timestamps. Authenticated,
user-scoped endpoints under `/v1/recovery/backup`:

| Method | Route | Effect |
|---|---|---|
| `PUT` | `/v1/recovery/backup` | upsert the caller's sealed envelope (replaces prior) |
| `GET` | `/v1/recovery/backup` | return the caller's envelope, or 404 |
| `DELETE` | `/v1/recovery/backup` | remove the caller's backup (idempotent) |

`PUT` is throttled (6/min) — a backup is written rarely. There is no way to
address another user's row; the user id comes from the access token, never the
request body.

This half is useful on its own: the client can seal the identity material and
upload it (mobile "create backup" UI), and re-download it to verify while still
authenticated. It does **not** by itself solve recovery-after-loss, which is
the retrieval problem below.

## The open decision: lost-device retrieval auth

By definition, a user recovering from a **lost** device cannot present that
device's identity key or a normal access token. So retrieval needs an auth
path that survives device loss. Candidates, each with a tradeoff:

1. **Handle + passphrase, server returns the encrypted blob.** Simplest UX.
   Risk: an unauthenticated endpoint keyed by a public handle lets anyone pull
   *any* user's (encrypted) blob and brute-force the passphrase offline. PBKDF2
   600k slows but does not stop a weak-passphrase attack. Needs strict
   per-handle rate limiting + a high-entropy passphrase requirement, and it
   still leaks "this handle has a backup."
2. **Recovery code (high-entropy, shown once at backup time).** The code — not
   the handle — addresses the blob, and ideally is mixed into the KDF. An
   attacker without the code cannot even fetch the ciphertext. Strongest, but
   the user must store the code somewhere durable (the classic seed-phrase UX),
   which many users won't.
3. **Out-of-band re-attestation** (e.g. a second pre-registered device, or a
   trusted contact threshold). Strongest trust model, heaviest to build, and at
   odds with the single-device simplicity goal.

**Recommendation to revisit at decision time:** option 2 (recovery code as the
retrieval key, mixed into the KDF) — it keeps the server zero-knowledge *and*
keeps the ciphertext itself unfetchable without the code, so a weak passphrase
alone can't sink a user. This needs sign-off (and ideally external review)
before the retrieval endpoint is built.

## Deliberately deferred

- the unauthenticated/alternate-auth **retrieval** endpoint (the decision above)
- mobile **create-backup** and **restore** UI flows (the create flow can be
  built now against `PUT`; restore waits on the retrieval decision)
- what exactly goes *inside* the envelope (identity keypair only vs. + per-
  conversation keys vs. + ratchet state) — a separate serialization spec
- backup freshness / staleness prompts after key rotation

## Test matrix (storage substrate — shipped)

| # | Scenario | Expected |
|---|---|---|
| 1 | PUT new backup | row created, updatedAt returned |
| 2 | PUT again | prior row replaced (upsert update branch) |
| 3 | GET with a backup | ciphertext + format + updatedAt |
| 4 | GET with no backup | 404 |
| 5 | DELETE existing | deleted=true |
| 6 | DELETE nonexistent | deleted=false (idempotent) |
| 7 | another user's token | only ever sees their own row (user id from token) |
