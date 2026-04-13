# VEIL Crypto Session State Migration

Last updated: 2026-04-11

This document defines how VEIL should migrate from the current mock-backed
conversation bootstrap metadata to a future audited real crypto session-state
model.

This is a migration design document, not proof that the migration is already
implemented.

Related docs:

- [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
- [crypto-mobile-bridge-design.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-mobile-bridge-design.md)
- [mock-crypto-replacement.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/mock-crypto-replacement.md)

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
