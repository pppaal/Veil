# VEIL Audited Crypto Adapter Execution Plan

Last updated: 2026-04-13

This document is the execution checklist for replacing VEIL's mock crypto
adapter with an audited real adapter.

It does not authorize production release by itself.

## Outcome required

At the end of this work, VEIL must have:

- an audited cryptographic library decision
- a Flutter mobile bridge strategy
- a real adapter implementation behind the existing boundaries
- interoperability fixtures and migration tests
- documented rollback and failure handling

It must still preserve:

- no backup
- no recovery
- device-bound identity
- old-device-required trusted-device join
- server ciphertext-only handling

## Decision gates

### Gate 1: library selection

Required:

- audited library provenance is documented
- license is acceptable
- Android and iOS integration paths are clear
- session primitives cover identity, prekeys, and per-peer session state

`No-Go` if:

- the library requires server-side private-key handling
- the library forces recovery-style cloud state
- the Flutter bridge plan is unclear

### Gate 2: bridge architecture

Required:

- Android bridge design
- iOS bridge design
- Flutter boundary surface
- secure local storage ownership rules

`No-Go` if:

- app/business logic must be rewritten outside the current adapter boundary
- private key material would leave the device

### Gate 3: adapter implementation readiness

Required:

- identity generation path
- signed prekey generation/rotation path
- session bootstrap/state path
- message encrypt/decrypt path
- attachment wrap/unwrap path
- interoperability fixtures

`No-Go` if:

- envelope serialization drifts without an explicit migration plan
- revoke/transfer semantics regress

## Work breakdown

### 1. Library selection

Owner:
- security/architecture lead

Tasks:
- shortlist candidate audited libraries
- document supported primitives
- document mobile platform support
- document license and maintenance posture
- record why rejected options were rejected

Required artifact:
- `docs/audited-crypto-library-decision.md`

Current recommendation:
- [audited-crypto-library-decision.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-library-decision.md)

### 2. Flutter bridge design

Owner:
- mobile platform engineer

Tasks:
- decide `platform channel` vs `FFI` vs mixed approach
- define Android ownership
- define iOS ownership
- define how secure local references are surfaced to Dart
- define failure and upgrade semantics

Required artifact:
- `docs/crypto-mobile-bridge-design.md`

Current bridge design draft:
- [crypto-mobile-bridge-design.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-mobile-bridge-design.md)

### 3. Adapter contract mapping

Owner:
- mobile/app architecture engineer

Tasks:
- map selected library primitives to:
  - `DeviceIdentityProvider`
  - `DeviceAuthChallengeSigner`
  - `ConversationSessionBootstrapper`
  - `MessageCryptoEngine`
  - attachment key wrapping boundary
- confirm `CryptoEnvelopeCodec` stability or versioned migration need
- confirm fixture contract coverage

Relevant files:
- [crypto_engine.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/crypto_engine.dart)
- [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md)
- [crypto-interoperability-fixtures.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-interoperability-fixtures.md)

### 4. Local state and migration design

Owner:
- mobile storage engineer

Tasks:
- define real session-state storage format
- define migration from current versioned bootstrap metadata
- define wipe/revoke/logout behavior
- define behavior when remote identity fingerprint changes

Current migration boundary already present:
- `sessionSchemaVersion`
- `localDeviceId`
- `remoteDeviceId`
- `remoteIdentityFingerprint`

Required artifact:
- `docs/crypto-session-state-migration.md`

### 5. Interoperability fixture implementation

Owner:
- crypto integration engineer

Tasks:
- emit versioned fixture set for:
  - identity
  - device auth signing
  - recipient bundle decode
  - session bootstrap
  - attachment wrap
  - message encrypt/decrypt
- verify mobile/shared contract compatibility

Relevant files:
- [packages/shared/src/crypto/fixtures.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/fixtures.ts)
- [docs/crypto-interoperability-fixtures.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-interoperability-fixtures.md)

### 6. Integration and regression testing

Owner:
- app/backend QA engineer

Required tests:
- sender/receiver interoperability
- local cache migration
- device transfer after crypto replacement
- revoke invalidation after crypto replacement
- attachment wrap/unwrap compatibility
- no plaintext leakage into logs or push payloads

### 7. Security review handoff

Owner:
- security lead

Tasks:
- update review packet
- declare exact library and bridge choice
- document remaining assumptions
- hand off for external review

Relevant docs:
- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [private-beta-audit.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-audit.md)

## Explicit non-go conditions

Do not proceed to production if any of these remain true:

- mock adapter still active in the shipping build
- external review has not covered the new crypto path
- revoke/transfer semantics changed without re-verification
- local session migration can strand or silently wipe device state

## What can remain unchanged

These areas should not need architectural redesign:

- API message lifecycle
- local outbox/retry/reconnect flows
- trusted-device graph product model
- attachment ticket and relay structure
- no-recovery UX and policy

## Bottom line

This work is successful only if audited crypto replaces the adapter without
forcing VEIL to weaken its privacy model or rewrite product logic outside the
existing boundary.
