# VEIL Crypto Session State Migration

Last updated: 2026-11-11

This document defines how VEIL should migrate from the current mock-backed
conversation bootstrap metadata to a future audited real crypto session-state
model.

This is a migration design document, not proof that the migration is already
implemented.

Related docs:

- [audited-crypto-adapter-execution.md](docs/audited-crypto-adapter-execution.md)
- [crypto-mobile-bridge-design.md](docs/crypto-mobile-bridge-design.md)
- [mock-crypto-replacement.md](docs/mock-crypto-replacement.md)

## Migration goal

Move VEIL from:

- versioned mock bootstrap metadata

to:

- versioned audited-crypto session metadata plus native-owned session state

without:

- introducing any recovery semantics
- moving private key or session secrets server-side
- silently corrupting device-local conversation state

## Current persisted metadata

VEIL already persists migration-oriented metadata around conversation state:

- `sessionSchemaVersion`
- `localDeviceId`
- `remoteDeviceId`
- `remoteIdentityFingerprint`

This is intentionally not enough to recreate real cryptographic state. It is
only enough to help detect when a native session-state reference must be
recreated or invalidated.

## Dart protocol v2 session state (implemented)

The default in-Dart adapter already persists real ratchet state (it is the
default build until libsignal is). Its on-device format and the migrations it
performs:

### Snapshot schema v4

```json
{
  "v": 4,
  "rev": 1762851234567890,
  "current": { "protocol": 2, "rootKey": "...", "...": "..." },
  "archived": [{ "archivedAt": "2026-11-11T09:00:00.000Z", "state": { "...": "..." } }]
}
```

- One record per conversation: the sending state plus up to five archived
  states (30 days) that still receive in-flight messages after a
  re-bootstrap, a peer reset or glare.
- `rev` only grows. The adapter persists every commit and waits for the write
  before the operation returns; storage refuses a write whose `rev` is lower
  than the one it holds, so a slow older write can never overwrite a newer
  state. `rev` is seeded from the clock (microseconds) so a re-created record
  outranks a stale stored one.
- A state map records its `protocol`: `2` for X3DH sessions, `1` for legacy
  `veil-envelope-v1` sessions, which keep working with peers that still
  publish v1 bundles and are reported as `legacyUnauthenticated`.

### Restoring older snapshots

- v3 (and v2) snapshots were a single legacy-protocol state; they restore as
  the `current` state of a fresh record (`protocol` 1). Nothing is re-keyed
  and no trust is invented: they stay legacy-unauthenticated until the peer
  starts a v2 session.
- Unreadable or unknown-version snapshots are skipped; the conversation
  re-bootstraps on the next send.
- A restore never replaces an in-memory record with a higher `rev`.

### Storage layout migration

- Before v4, all snapshots lived in one secure-storage blob
  (`veil.crypto.session_snapshots`), and concurrent writers lost updates.
  Now each conversation has its own key, `veil.crypto.session.<sha256hex(conversationId)>`,
  listed in `veil.crypto.session_index` (FlutterSecureStorage cannot enumerate
  keys portably). The id is hashed so key names never carry it.
- The legacy blob is migrated once, on first access, and deleted; a restart
  never re-applies it.
- Session, group sender-key and prekey writes share one serial queue.

### Identity refs and prekeys

- New identities are v2 refs (`{v: 2, ed25519, x25519, spk}`); v1 refs keep
  working. `rotateSignedPrekey` upgrades a v1 ref (its X25519 key becomes the
  certified IKx) and returns `upgradedIdentityPrivateRef` for the caller to
  persist in place of the old one.
- Prekey private halves live under `veil.crypto.opk.<id>` /
  `veil.crypto.spk.<id>` plus `veil.crypto.prekey_index`, which also holds the
  next one-time prekey id so ids are never reused.

### Wipe

`wipeLocalDeviceState` clears session records, group sender keys, prekey
private halves and the identity, exactly as Rule 3 below requires.

## Target model

After audited crypto integration:

- Dart should still persist only migration-safe metadata
- native code should own real session-state bytes
- Dart should hold only opaque native references or handles where needed

## Migration rules

### Rule 1. No silent trust carry-over

If the old mock-backed state cannot be upgraded safely:

- invalidate it
- force a fresh per-peer bootstrap

Do not silently treat mock-backed state as if it were audited crypto state.

### Rule 2. Remote identity changes are explicit

If `remoteIdentityFingerprint` changes unexpectedly:

- mark the session invalid
- require re-bootstrap
- surface a safe local trust-state message

Do not silently continue.

### Rule 3. Wipe behavior remains strict

On any of the following:

- logout
- local wipe
- revoke
- device_not_active

VEIL must clear:

- native crypto session state
- native key references that are no longer valid
- matching migration-safe metadata in the local cache

### Rule 4. No server-assisted recovery

Migration must not depend on:

- backup restore
- server-held key escrow
- password reset
- hidden device restore logic

## Required migration states

At minimum, each conversation session should end up in one of these states:

- `legacy_mock_state`
- `needs_rebootstrap`
- `active_native_state`
- `fingerprint_mismatch`
- `wiped`

## Expected migration flow

1. Load persisted conversation metadata
2. Check `sessionSchemaVersion`
3. If the state is mock-backed or version-mismatched:
   - mark `needs_rebootstrap`
4. On next send/receive/bootstrap:
   - create audited native session state
   - store native-owned reference
   - update migration-safe metadata
5. If native state creation fails:
   - keep the conversation non-recoverable
   - do not invent a plaintext fallback

## No-go conditions

Do not ship migration if any of these are true:

- mock state is silently treated as production session state
- native state wipe is incomplete on revoke or logout
- fingerprint changes are ignored
- migration requires server recovery or user credential reset

## Test requirements

Minimum tests after implementation:

- legacy conversation metadata upgrades into `needs_rebootstrap`
- fresh bootstrap creates audited native session state
- logout clears both metadata and native state
- revoke clears both metadata and native state
- fingerprint change forces re-bootstrap
- attachment/message send still fail closed if native session is missing

## Success condition

Migration is successful only if:

- VEIL preserves device-bound trust
- losing all devices remains unrecoverable
- local session state becomes audited-crypto compatible
- business logic outside the adapter boundary does not need a redesign
