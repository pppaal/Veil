# VEIL Crypto Adapter Architecture

VEIL now uses a production crypto adapter (`LibCryptoAdapter`) built on X25519 ECDH key exchange, AES-256-GCM authenticated encryption, HKDF-SHA256 key derivation, and Ed25519 identity signing. The mock adapter remains available for unit tests only.

## Production adapter: LibCryptoAdapter

The production adapter is implemented in `lib_crypto_adapter.dart` and provides:

- `_LibDeviceIdentityProvider`: Ed25519 identity keys + X25519 prekey bundles
- `_LibKeyBundleCodec`: API key bundle parsing
- `_LibCryptoEnvelopeCodec`: envelope version `veil-envelope-v1`
- `_LibSessionBootstrapper`: X25519 ECDH shared secret via HKDF-SHA256
- `_LibMessageCryptoEngine`: AES-256-GCM encrypt/decrypt with ephemeral key prepended (32 bytes) and MAC appended (16 bytes)
- Attachment encryption: random content key, X25519 DH wrap, algorithm hint `x25519-aes256gcm`

The adapter is registered through `crypto_adapter_registry.dart` and is the default for all runtime builds.

## What remains unchanged

These areas remained stable during production crypto integration:

- REST and realtime message lifecycle
- ciphertext-only server storage model
- no-recovery product philosophy
- device-bound identity model
- old-device-required transfer model
- attachment upload ticket and encrypted-reference architecture
- message queue, retry, reconnect, and receipt flows

## What changed for production crypto

Only the adapter layer changed materially:

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
- [lib_crypto_adapter.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart)
- [mock_crypto_engine.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/mock_crypto_engine.dart) (test-only)
- [packages/shared/src/crypto/types.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/types.ts)

Runtime consumption:

- session bootstrap material is consumed by the mobile messaging flow when a
  peer device bundle is selected
- bootstrap metadata is persisted in the local conversation cache so adapter
  upgrades replace only the adapter/session-state implementation rather than
  the controller or UI flow
- persisted bootstrap metadata includes:
  - `sessionSchemaVersion`
  - `localDeviceId`
  - `remoteDeviceId`
  - `remoteIdentityFingerprint`
  so adapters can detect stale local state and bind stored session material
  to the correct trusted-device edge

## Storage implications

The production adapter requires additional local state:

- identity private key material
- signed prekeys and rotation state
- per-peer session state
- attachment content keys or wrapped-key state
- versioned session-state storage keyed to the local/remote device pair

What should not change:

- private key material stays on-device
- server does not receive device private keys
- server remains ciphertext-only
- no recovery path is introduced

## Testing implications

With production crypto integrated, these tests should expand:

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

1. Session-state shape has grown, and careless storage migration can wipe or corrupt local conversations.
2. Device-graph changes can invalidate persisted session state if local/remote
   device binding is not checked during migration.
3. Attachment encryption failures can create silent UX regressions if wrap/unwrap semantics drift.
4. Transfer and revoke must be re-verified with real session material.
5. Production crypto can expose ordering and replay assumptions that the mock adapter did not.
6. Any claim of production cryptographic safety before external review would be premature.

## External review checklist

1. Production adapter (`LibCryptoAdapter`) is integrated behind the existing interfaces.
2. `crypto_adapter_registry.dart` remains the only runtime selection point.
3. API contract preserved with versioned envelope (`veil-envelope-v1`).
4. Interoperability fixtures for sender, receiver, attachment, and transfer flows should be expanded.
5. Persisted session metadata preserved:
   - schema version
   - local device id
   - remote device id
   - remote identity fingerprint
6. Review secure storage lifecycle for revoke, logout, wipe, and transfer.
7. Run external security review before any production claim or production boot enablement.

The future fixture contract is defined in:

- [packages/shared/src/crypto/fixtures.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/fixtures.ts)
- [crypto-interoperability-fixtures.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-interoperability-fixtures.md)
