# VEIL Crypto Interoperability Fixtures

VEIL does not ship production cryptography yet. This document defines the
fixture contract that future audited adapters must emit so that replacement can
be validated without changing product logic.

Authoritative code contract:

- [packages/shared/src/crypto/fixtures.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/fixtures.ts)

## Purpose

These fixtures are for test and review only. They are not a runtime protocol.

They exist to prove that a future audited adapter can:

- generate device identity material
- generate device-auth signing material
- decode a directory key bundle
- bootstrap per-peer session state
- encrypt attachment wrap material
- encrypt and decrypt a message envelope

without rewriting:

- auth controller flow
- conversation and message lifecycle
- attachment ticket flow
- transfer and revoke product rules
- local cache and search behavior

## Required fixture sections

Every fixture must include:

1. `identity`
   - generated device identity material
   - generated device-auth key material
2. `recipientBundle`
   - decoded public key bundle for the remote device
3. `session`
   - session bootstrap request
   - session bootstrap result
   - persistence expectation for:
     - local device id
     - remote device id
     - remote identity fingerprint
     - session schema version
4. `attachment`
   - wrapped attachment content-key material
5. `message`
   - ciphertext envelope
   - expected decrypted body

## Storage implications

Real audited crypto will expand local storage beyond the current private-beta
mock:

- session state locators will need real session material behind them
- signed prekey rotation state will need persistence
- attachment wrap fixtures will need compatibility coverage across adapter
  versions

Private key material must remain device-side. Fixture generation must never
upload private keys to the server.

## Testing implications

When a real adapter lands, fixture coverage must be added in three places:

- mobile adapter tests
- shared serialization compatibility tests
- backend contract serialization tests

At minimum, fixture assertions must prove:

- stable envelope serialization
- stable attachment wrap serialization
- stable session bootstrap material shape
- stable session persistence metadata shape
- no plaintext message body leaves the adapter boundary

## Rollout risks

- A real adapter can change session-state volume and migration behavior.
- Attachment wrapping can drift from the message adapter if fixtures are not
  versioned together.
- Device transfer must be re-verified once session bootstrap material becomes
  real state.

Any production claim remains invalid until audited crypto replaces the mock
adapter and external review is complete.
