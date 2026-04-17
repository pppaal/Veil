# Crypto Replacement Status

The mock crypto adapter has been replaced with a production `LibCryptoAdapter`.

## Current state

- The production adapter (`lib_crypto_adapter.dart`) is integrated and active for all runtime builds.
- X25519 ECDH key exchange, AES-256-GCM encryption, HKDF-SHA256 derivation, Ed25519 signing.
- Envelope version: `veil-envelope-v1`. Attachment algorithm hint: `x25519-aes256gcm`.
- The mock adapter remains available for unit tests only.
- The API stores opaque ciphertext payloads, nonces, and attachment metadata (unchanged).

See the adapter architecture in [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md).

## Design constraints (preserved)

1. Adapter boundary remains intact.
2. Only the adapter implementation changed, not the app or API message flow.
3. Uses `cryptography` Dart package primitives. No custom cryptography invented.
4. Private key material stays on-device only.
5. Server remains an encrypted relay and metadata store only.

## What was replaced

1. `DeviceIdentityProvider`: now generates real Ed25519 identity keys and X25519 signed prekey bundles.
2. `MessageCryptoEngine`: now uses AES-256-GCM with ephemeral keys and per-conversation HKDF-derived shared secrets.
3. Attachment key wrapping: now uses X25519 DH wrap with random content keys.
4. `KeyBundleCodec` and `CryptoEnvelopeCodec`: updated for production envelope version.
5. Session bootstrap persistence semantics preserved:
   - `sessionSchemaVersion`
   - `localDeviceId`
   - `remoteDeviceId`
   - `remoteIdentityFingerprint`
6. Interoperability tests and versioned fixtures should be expanded:
   - [packages/shared/src/crypto/fixtures.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/packages/shared/src/crypto/fixtures.ts)
   - [crypto-interoperability-fixtures.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-interoperability-fixtures.md)
7. External security review still required before production traffic.

## Non-negotiable constraints

- No server-side decryption.
- No recovery path.
- No plaintext message logging.
- No admin message viewer.
- No hidden debug bypass.
