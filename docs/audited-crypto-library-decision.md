# VEIL Audited Crypto Library Decision

Last updated: 2026-04-13

This document records the current recommendation for VEIL's future audited
crypto adapter.

It is a decision-support document, not proof that the integration is complete.

## VEIL constraints

Any candidate must preserve:

- no backup
- no recovery
- device-bound identity
- old-device-required trusted-device join
- server ciphertext-only handling
- device-side private key ownership

Any candidate is a `No-Go` if it pushes VEIL toward:

- cloud recovery semantics
- server-side key custody
- product logic rewriting outside the existing adapter boundary

## Candidate summary

### Candidate A: Signal `libsignal`

Why it fits:

- widely recognized audited secure messaging lineage
- supports identity keys, signed prekeys, and session state
- maps conceptually to VEIL's adapter boundary
- strong fit for a device-bound private messenger

Challenges:

- Flutter integration requires a native bridge strategy
- VEIL must define mobile platform ownership clearly
- session-state migration from the current mock boundary must be designed carefully

Current recommendation:

- `Preferred candidate`

### Candidate B: MLS-focused stack

Why it is less suitable right now:

- VEIL is not adding groups or cloud-synced multi-party state in this phase
- would add unnecessary architectural weight for the current direct-messaging scope

Current recommendation:

- `Not preferred for current phase`

### Candidate C: ad hoc custom cryptography

Why it is rejected:

- violates VEIL's explicit rule against custom production cryptography
- increases review and interoperability risk
- would make production claims indefensible

Current recommendation:

- `Rejected`

## Current recommendation

Use an audited Signal-style session library as the basis for the future VEIL
adapter, with a native mobile bridge for Flutter.

Working decision:

1. prefer a `libsignal`-class audited session library
2. keep the existing VEIL adapter boundary
3. bridge native crypto into Flutter rather than reimplementing crypto in Dart

This is still subject to:

- license confirmation
- mobile bridge feasibility
- secure storage lifecycle review

## Why this recommendation fits VEIL

It preserves:

- device-bound identity
- per-device trust graph
- old-device-required join
- ciphertext-only relay behavior

It does not require:

- cloud recovery
- phone-number-first identity
- plaintext server search

## Planned bridge shape

Recommended direction:

- Android: native Kotlin integration
- iOS: native Swift integration
- Flutter: platform channel boundary first

Why platform channel first:

- lowers risk versus inventing low-level crypto bindings
- keeps audited library ownership in native code
- maps cleanly to VEIL's existing `CryptoAdapter` interfaces

FFI can be reconsidered later only if:

- the audited library distribution model is compatible
- operational complexity is lower than platform channels

## Decision gates still open

Before final sign-off, confirm:

1. library license is acceptable
2. library maintenance posture is acceptable
3. Android and iOS bridges are realistic for the team
4. secure storage behavior for key/session material is defined
5. interoperability fixtures can be emitted without changing product logic

## Required next artifacts

- [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
- [crypto-mobile-bridge-design.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-mobile-bridge-design.md)
- `docs/crypto-session-state-migration.md`

## Non-claims

This document does not mean:

- audited crypto is integrated
- production cryptography is ready
- external review is complete

It only means VEIL now has a concrete preferred direction.
