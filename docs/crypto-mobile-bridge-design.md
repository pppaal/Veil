# VEIL Crypto Mobile Bridge Design

Last updated: 2026-04-07

This document defines the recommended mobile bridge shape for integrating an
audited real crypto library into VEIL.

It does not mean the audited adapter is already implemented.

## Goal

Integrate audited crypto into VEIL mobile without:

- changing product philosophy
- moving sensitive material server-side
- leaking private key material into app/business logic
- rewriting messaging flows outside the current adapter boundary

## Recommended direction

Preferred bridge model:

- Android: native Kotlin bridge
- iOS: native Swift bridge
- Flutter: platform channel boundary

This should remain behind the current `CryptoAdapter` interfaces in:

- [crypto_engine.dart](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/lib/src/core/crypto/crypto_engine.dart)

## Why platform channels first

Why this is preferred over a direct Dart reimplementation:

- audited crypto ownership stays in native code
- mobile platform secure storage APIs stay close to the crypto library
- the boundary between app logic and crypto state remains explicit
- the team avoids inventing low-level crypto plumbing in Dart

FFI is not rejected forever, but it should only be chosen if:

- the audited library packaging fits both Android and iOS cleanly
- lifecycle complexity is lower than platform channels
- secure key/session storage ownership remains clear

## Boundary shape

The Dart side should continue depending on:

- `DeviceIdentityProvider`
- `DeviceAuthChallengeSigner`
- `ConversationSessionBootstrapper`
- `MessageCryptoEngine`
- `CryptoEnvelopeCodec`
- `CryptoAdapter`

The Dart side must not:

- hold raw private keys
- implement session primitives directly
- bypass the adapter registry

## Android ownership

Recommended ownership:

- Kotlin module owns audited library calls
- Android secure storage owns local key references
- platform channel methods return only safe adapter outputs to Dart

Android native responsibilities:

- generate identity keys and signed prekeys
- create and update per-peer session state
- sign auth challenges if platform-backed auth is chosen
- encrypt/decrypt messages
- wrap/unwrap attachment content keys
- wipe local crypto state on revoke/logout/local wipe

Android must not send private keys or session state to the backend.

## iOS ownership

Recommended ownership:

- Swift module owns audited library calls
- Keychain / secure enclave backed references stay native where possible
- platform channel methods return only safe adapter outputs to Dart

iOS native responsibilities mirror Android:

- identity generation
- signed prekey lifecycle
- per-peer session state
- auth challenge signing if needed
- message encrypt/decrypt
- attachment key wrap/unwrap
- local wipe on revoke/logout/device wipe

## Flutter boundary

Recommended channel pattern:

- one `VeilCryptoBridge` surface per platform
- narrow message-based methods mapped to adapter use cases

Suggested method groups:

1. `generateDeviceIdentity`
2. `generateAuthKeyMaterial`
3. `signChallenge`
4. `bootstrapSession`
5. `encryptMessage`
6. `decryptMessage`
7. `encryptAttachmentKey`
8. `wipeCryptoState`

The Flutter side should receive:

- public identity material
- secure local references
- versioned session bootstrap metadata
- encrypted envelopes
- wrapped attachment material

The Flutter side should not receive:

- raw long-term private keys
- serialized per-peer session secrets except through safe opaque references

## Session-state ownership

Current VEIL already persists migration-ready metadata:

- `sessionSchemaVersion`
- `localDeviceId`
- `remoteDeviceId`
- `remoteIdentityFingerprint`

Future audited crypto should keep this model:

- Dart stores only migration-safe metadata and opaque local references
- native platform code owns actual session-state bytes

This reduces the chance that:

- cached app data leaks raw session material
- app logic accidentally manipulates sensitive state

## Failure behavior

Bridge failures must be explicit and non-silent.

Required behavior:

- crypto method failures return typed errors
- Flutter converts them to safe user-facing states
- no raw provider/library exceptions should be surfaced directly to users
- no plaintext fallback path is allowed

## Migration behavior

When real crypto is introduced:

- existing mock-backed session metadata must be invalidated or migrated safely
- remote identity fingerprint mismatch must force re-bootstrap
- revoke/logout/local wipe must clear native session state and local references

No migration path may introduce recovery semantics.

## Security rules

Non-negotiable:

- private key material remains on device
- server remains ciphertext-only
- no hidden debug bridge methods
- no admin decrypt path
- no plaintext logging of bridge inputs or outputs

## Test requirements

Bridge integration is not acceptable without:

- Android native integration tests
- iOS native integration tests
- Flutter adapter integration tests
- cross-device interoperability tests
- migration tests for session metadata and local wipe
- transfer/revoke retests after audited crypto activation

## Go / no-go

`Go` when:

- the native bridge maps cleanly to the current adapter boundary
- local storage ownership is clear
- no private-key leakage path exists
- migration behavior is defined

`No-Go` when:

- Dart must handle raw key/session secrets directly
- product logic outside the adapter boundary must change materially
- platform implementations drift in incompatible ways

## Related docs

- [audited-crypto-library-decision.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-library-decision.md)
- [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
- [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md)
