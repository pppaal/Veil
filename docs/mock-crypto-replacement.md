# Mock Crypto Replacement Plan

The current VEIL repository preserves the encrypted-envelope architecture, but it does not provide production cryptographic safety.

## Current state

- Mobile and backend contracts are already built around a crypto adapter boundary.
- The API only stores opaque ciphertext-like payloads, nonces, and attachment metadata.
- The current adapters are mock-only and must not ship to production.

See the current adapter split in [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md).

## Replacement requirements

1. Keep the adapter boundary intact.
2. Replace only the adapter implementation first, not the app and API message flow.
3. Use audited messaging/session primitives. Do not invent custom cryptography.
4. Keep private key material on-device only.
5. Keep the server as an encrypted relay and metadata store only.

## Exact steps

1. Replace `DeviceIdentityProvider` with real identity key generation, signed prekeys, and session bootstrap state.
2. Replace `DeviceAuthChallengeSigner` only if platform-keystore backed device auth changes are required.
3. Replace `MessageCryptoEngine` with audited per-conversation session encryption.
4. Replace mock attachment key wrapping with audited recipient-specific attachment key encryption.
5. Keep `KeyBundleCodec` and `CryptoEnvelopeCodec` stable unless a versioned envelope migration is required.
6. Add interoperability tests between:
   - mobile sender
   - mobile receiver
   - backend contract serialization
7. Run external security review before enabling production traffic.

## Non-negotiable constraints

- No server-side decryption.
- No recovery path.
- No plaintext message logging.
- No admin message viewer.
- No hidden debug bypass.
