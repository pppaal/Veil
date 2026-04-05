# VEIL Crypto Adapter Architecture

VEIL still uses mock crypto in private beta. This document defines the boundary that an audited real adapter must satisfy later.

## What remains unchanged

These areas should remain stable when real audited cryptography is introduced:

- REST and realtime message lifecycle
- ciphertext-only server storage model
- no-recovery product philosophy
- device-bound identity model
- old-device-required transfer model
- attachment upload ticket and encrypted-reference architecture
- message queue, retry, reconnect, and receipt flows

## What must change for real crypto

Only the adapter layer should change materially:

1. Device identity generation
2. Signed prekey generation and storage
3. Device auth challenge signing backend
4. Session bootstrap and per-peer session state
5. Message encrypt/decrypt
6. Attachment key wrapping

The current mobile boundary is split into:

- `DeviceIdentityProvider`
- `DeviceAuthChallengeSigner`
- `KeyBundleCodec`
- `ConversationSessionBootstrapper`
- `CryptoEnvelopeCodec`
- `MessageCryptoEngine`
- `CryptoAdapter`

Files:

- [crypto_engine.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/crypto_engine.dart)
- [crypto_adapter_registry.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/crypto_adapter_registry.dart)
- [mock_crypto_engine.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/mock_crypto_engine.dart)
- [packages/shared/src/crypto/types.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/types.ts)

Current private-beta consumption:

- session bootstrap material is now consumed by the mobile messaging flow when a
  peer device bundle is selected
- bootstrap metadata is persisted in the local conversation cache so an audited
  adapter can later replace only the adapter/session-state implementation rather
  than the controller or UI flow

## Storage implications

Real audited crypto will require additional local state beyond the current private-beta mock:

- identity private key material
- signed prekeys and rotation state
- per-peer session state
- attachment content keys or wrapped-key state

What should not change:

- private key material stays on-device
- server does not receive device private keys
- server remains ciphertext-only
- no recovery path is introduced

## Testing implications

When real crypto is integrated, these tests must expand:

- cross-device interoperability tests
- fixture compatibility tests against a versioned interoperability fixture contract
- serialization compatibility tests across mobile and API
- attachment wrap/unwrap compatibility tests
- migration tests from mock-cache state to real session state
- transfer tests that prove new-device possession with real key material

Current architecture checks already assert:

- app state does not import the mock adapter directly
- messaging controller does not depend on mock protocol constants
- cache code does not depend on mock protocol constants
- the shared package root does not export the mock adapter by default

## Rollout risks

1. Session-state shape will grow, and careless storage migration can wipe or corrupt local conversations.
2. Attachment encryption failures can create silent UX regressions if wrap/unwrap semantics drift.
3. Transfer and revoke must be re-verified once real session material exists.
4. Real crypto can expose ordering and replay assumptions that the mock adapter does not.
5. Any claim of production cryptographic safety before external review would be false.

## Migration checklist

1. Implement an audited adapter behind the existing interfaces.
2. Keep `crypto_adapter_registry.dart` as the only runtime selection point.
3. Preserve the current API contract unless a versioned envelope migration is explicitly required.
4. Add interoperability fixtures for sender, receiver, attachment, and transfer flows.
5. Review secure storage lifecycle for revoke, logout, wipe, and transfer.
6. Run external security review before any production claim or production boot enablement.

The future fixture contract is defined in:

- [packages/shared/src/crypto/fixtures.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/fixtures.ts)
- [crypto-interoperability-fixtures.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-interoperability-fixtures.md)
