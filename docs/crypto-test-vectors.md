# Crypto known-answer test vectors

Machine-checkable, independently-reproducible known-answer test (KAT) vectors
for the primitives VEIL's 1:1 message crypto is built on, and full protocol
transcripts for the legacy v1 schedule and protocol v2. Purpose: let an
external auditor — and any replacement engine (the mobile Dart adapter, the web
port, or a future libsignal-backed engine) — verify that an implementation
produces the correct output for known inputs, without trusting VEIL's own code.

- Vectors: [`packages/shared/test-vectors/crypto-kat.json`](../packages/shared/test-vectors/crypto-kat.json)
- Generator / checker: [`scripts/crypto-test-vectors.mjs`](../scripts/crypto-test-vectors.mjs)
- Spec these primitives compose into: [`crypto-envelope-spec.md`](crypto-envelope-spec.md)
- Dart replay of protocol v2: [`apps/mobile/test/crypto/crypto_kat_v2_test.dart`](../apps/mobile/test/crypto/crypto_kat_v2_test.dart)

## What is covered

| Primitive | Algorithm | Anchor |
|---|---|---|
| ECDH | X25519 (RFC 7748) | RFC 7748 §6.1 (Alice/Bob) |
| Signatures | Ed25519 (RFC 8032, deterministic) | deterministic KAT from a fixed seed |
| KDF | HKDF-SHA256 (RFC 5869) | RFC 5869 §A.1 |
| AEAD | AES-256-GCM | deterministic KAT (fixed key/nonce/AAD) |

### Legacy v1 schedule (`vectors.protocol`)

Composes those primitives exactly the way the legacy `veil-envelope-v1`
protocol does:

| Vector | What it pins |
|---|---|
| `sessionSetup` | bootstrap `sharedSecret` → `rootKey` / `chainKeyA` / `chainKeyB` under the `veil-root-v2` / `veil-chain-A-v2` / `veil-chain-B-v2` labels, salt = `utf8(conversationId)`, plus the lexicographic deviceId chain-assignment rule |
| `dhRatchetStep` | 64-byte `veil-dh-rk-v2` HKDF split into `newRootKey` + `newSendChainKey` |
| `messageChain` | three symmetric-ratchet steps: `veil-msg-n<counter>` / `veil-msg-v1` message keys and the `[0x00]` / `veil-chain-next-v1` chain advance |
| `frame` | a full wire frame: ISO/IEC 7816-4 padding to the 256-byte bucket, AES-256-GCM under the `veil-frame-aad-v3` AAD (`label ‖ ratchetPub ‖ counter(4 BE) ‖ senderDeviceId`), and `frameHex = ratchetPub ‖ counter ‖ ciphertext ‖ tag` |
| `frame.tamperedHeader` | the same ciphertext with the AAD rebuilt from a flipped header counter **must fail** GCM verification (`decryptFails: true`) |

### Protocol v2 (`vectors.protocolV2`)

An independent node:crypto implementation of
[`crypto-envelope-spec.md`](crypto-envelope-spec.md) §"Protocol v2", run over a
fixed scenario. Every key and nonce is fixed and listed in the order the
adapter draws them, so a replay with a scripted random source must reproduce
every byte:

| Vector | What it pins |
|---|---|
| `constants` | every label, the envelope version, the attachment algorithm and the no-OPK id |
| `bundle` | contract C1: `ikxSig`, `spkSig` (with their signed messages), the compact bundle JSON and its b64u string, from IK seed `0x11`×32, IKx `0x55`×32, SPK `0x66`×32, spkId 1, spkTs 1767225600000 |
| `oneTimePrekey` | Bob's OPK (keyId 1) |
| `alice` | the initiator identity, her `ikxSig`, and her clock (inside the SPK freshness window) |
| `x3dh` | EK, DH1–DH4, the HKDF ikm/salt/info, `sharedKey`, `associatedData` and the 168-byte `preKeyHeader` |
| `ratchetInit`, `sendSteps` | Alice's initial sending chain and both send-side DH steps (Bob's first reply; Alice's turn with PN = 2) |
| `frames` | four frames (A0, A1 PreKey; B0, A2 Normal): header, AAD v4, inner payload JSON, padded plaintext, message key, ciphertext, tag, frame and the envelope `ciphertext`/`nonce` strings. Bob receives A0, A2, A1, so A1 is a straggler recovered through the PN stash |
| `attachment` | the attachment pointer cipher: Padmé padding, the `veil-att-v2` AAD, the blob, its digest and the inner-payload pointer A2 carries |
| `padme` | `padmeLength` for n = 1..10, 100, 1000, 65537, 1000000 |

The generator also proves, with the oracle, that every DH it emits is symmetric
(both sides derive it) and that every frame decrypts before it writes anything.

Every HKDF label, salt, field order, length prefix, JSON key order and counter
encoding in these vectors is wire format: an implementation that drifts on any
of them fails the vectors. Values are hex unless a field name says `b64u`, is a
JSON string, or is an envelope string (`envelopeCiphertext`, `envelopeNonce`).

## Why these are trustworthy

The generator is Node's own crypto (OpenSSL). To prove that oracle is itself
correct, the set pins **published RFC vectors** (RFC 7748 §6.1 for X25519,
RFC 5869 §A.1 for HKDF-SHA256) and the generator **asserts Node reproduces them
before emitting anything** — if OpenSSL disagreed with the RFC, generation would
abort. The remaining vectors use fixed inputs; every primitive here is
deterministic:

- Ed25519 signatures are deterministic by construction (RFC 8032), so a fixed
  seed + message yields one canonical signature across all correct
  implementations.
- HKDF and fixed-nonce AES-256-GCM are deterministic functions of their inputs.
- Protocol v2's only randomness (key pairs, nonces) is replaced by the listed
  fixed values.

So any correct implementation, fed the inputs in the JSON, must produce byte-
identical outputs. The Dart adapter is not the generator: it reproduces the
oracle's bytes independently.

## How to use them

**As an auditor / reviewer:** feed each `case`'s inputs to the implementation
under review and compare against the recorded outputs. For X25519, both
directions (alice×bobPublic and bob×alicePublic) must yield `sharedSecret`. For
Ed25519, signing `messageHex` under `seed` must yield `signature`, `signature`
must verify against `publicKey`, and the `tamperedMessageHex` must **fail**
verification (`tamperedVerifies: false`). For AES-256-GCM, encrypting
`plaintextHex` under `key`/`nonce`/`aad` must yield `ciphertext` + `tag`.

**As a protocol v2 port (the web client):** replay `vectors.protocolV2` the way
`crypto_kat_v2_test.dart` does: give Bob's adapter the draws `bundle.identitySeed,
bundle.ikxPrivate, bundle.spkPrivate, oneTimePrekey.private,
sendSteps.bob.ratchetPrivate, B0.nonce` and a clock of `bundle.spkTs`; give
Alice's the draws `alice.identitySeed, alice.ikxPrivate, alice.spkPrivate,
x3dh.ephemeralPrivate, ratchetInit.aliceRatchetPrivate, A0.nonce, A1.nonce,
sendSteps.alice.ratchetPrivate, A2.nonce` and a clock of `alice.clockMs`; run
the transcript and compare every envelope byte for byte.

**In CI:** `pnpm crypto:vectors:check` (wired into `ci:api`) regenerates in
memory and byte-compares against the committed JSON, failing on any drift. The
Node-version string in the file is ignored by the check, since it legitimately
varies across runners. The mobile suite replays `protocolV2` against the Dart
adapter on every run, and also checks each intermediate (DH1–DH4 from both
ends, the HKDF ikm, every root/chain step and message key) on its own so a
broken vector names the term that drifted.

**Regenerate:** `node scripts/crypto-test-vectors.mjs` (only when intentionally
adding/altering vectors — review the diff).

## Scope and limits

- The primitive-level KATs prove the building blocks; `protocol` pins the
  legacy derivation schedule; `protocolV2` pins a complete v2 transcript
  including a turn and a PN straggler.
- What the vectors do **not** cover: the remaining stateful policy (skip caps,
  eviction, TTL, replay classification, session records and glare, the
  responder's prekey lookups). Those are exercised by the mobile test suite
  (`apps/mobile/test/crypto/`) and by the fixture contract in
  [`crypto-interoperability-fixtures.md`](crypto-interoperability-fixtures.md).
- The legacy `vectors.protocol` set is checked against the oracle only; no Dart
  test replays it.
