# Envelope v3 — unified wire format (superseded)

## Status

**Superseded. Never implemented.** Both clients now speak protocol v2
(`veil-envelope-v2`), specified in
[crypto-envelope-spec.md](crypto-envelope-spec.md) § Protocol v2 and pinned
byte for byte by `packages/shared/test-vectors/crypto-kat.json`
(`vectors.protocolV2`):

- the mobile client: `LibCryptoAdapter`
  ([apps/mobile/lib/src/core/crypto/](../apps/mobile/lib/src/core/crypto/));
- the web demo: a WebCrypto port
  ([apps/web-demo/src/crypto/](../apps/web-demo/src/crypto/)) that
  reproduces every protocol-v2 vector
  (`apps/web-demo/__tests__/kat-v2.test.js`).

This page used to propose a third dialect, `veil-envelope-v3`, to unify the
mobile ratchet with the web demo's single-shot ECDH. Protocol v2 solves the
same problem differently: X3DH with signed and one-time prekeys
authenticates both parties, then a Double Ratchet with the previous-chain
length in every header carries the conversation. Nothing should be built
from the earlier draft; the questions it raised for review are answered by
the protocol v2 specification and its known-answer vectors.

## Claims of the earlier draft that were false

The draft described the web demo's static per-pair ECDH
(`veil-envelope-v1-dev`) as having **per-message forward secrecy via a fresh
nonce**. It never did. The nonce only salted an HKDF over one static X25519
secret per peer pair, so anyone who obtained either identity key could
derive every past and future message key of that pair. The format also had
no replay protection and no sender authentication beyond the shared secret.
The web demo no longer writes it; history that format holds stays readable,
badged as legacy, not forward-secret, sender not authenticated, and only
until the identity that wrote it is replaced.

The draft also assumed that after a device transfer **the new device reads
the old ciphertext**, because it "shares the same handle's identity". It
does not. Identity is device-bound: a transfer gives the new device a new
identity key and new prekeys, and no key material leaves the old device. The
ratchet's message keys are single-use, so ciphertext stored on the server
is not decryptable by the new device, nor by the old one a second time.
History lives only in each device's own encrypted local store.

## Where the topics of the draft went

| Draft topic | Protocol v2 |
| --- | --- |
| Single wire format for web and mobile | `veil-envelope-v2`, byte-compatible, shared vectors |
| Forward secrecy and post-compromise security | X3DH (DH4 with a one-time prekey) and the Double Ratchet |
| AEAD binding of routing fields | AAD `veil-frame-aad-v4`: version, conversation, sender device, message type, header, identities |
| Skipped keys | at most 200 per frame, 1000 per session (oldest evicted), 7-day lifetime |
| Session state on web | IndexedDB: ratchet private keys as non-extractable CryptoKeys, roots and chains sealed under a non-extractable key |
| Group chats | Sender Keys (`veil-group-v1`), outside this page |
