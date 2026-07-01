# Crypto known-answer test vectors

Machine-checkable, independently-reproducible known-answer test (KAT) vectors
for the primitives VEIL's 1:1 message crypto is built on. Purpose: let an
external auditor — and any replacement engine (the mobile Dart adapter, or a
future libsignal-backed engine) — verify that an implementation produces the
correct output for known inputs, without trusting VEIL's own code.

- Vectors: [`packages/shared/test-vectors/crypto-kat.json`](../packages/shared/test-vectors/crypto-kat.json)
- Generator / checker: [`scripts/crypto-test-vectors.mjs`](../scripts/crypto-test-vectors.mjs)
- Spec these primitives compose into: [`crypto-envelope-spec.md`](crypto-envelope-spec.md)

## What is covered

| Primitive | Algorithm | Anchor |
|---|---|---|
| ECDH | X25519 (RFC 7748) | RFC 7748 §6.1 (Alice/Bob) |
| Signatures | Ed25519 (RFC 8032, deterministic) | deterministic KAT from a fixed seed |
| KDF | HKDF-SHA256 (RFC 5869) | RFC 5869 §A.1 |
| AEAD | AES-256-GCM | deterministic KAT (fixed key/nonce/AAD) |

Every value in the JSON is hex.

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

So any correct implementation, fed the inputs in the JSON, must produce byte-
identical outputs. There is no implementation-specific randomness to reconcile.

## How to use them

**As an auditor / reviewer:** feed each `case`'s inputs to the implementation
under review and compare against the recorded outputs. For X25519, both
directions (alice×bobPublic and bob×alicePublic) must yield `sharedSecret`. For
Ed25519, signing `messageHex` under `seed` must yield `signature`, `signature`
must verify against `publicKey`, and the `tamperedMessageHex` must **fail**
verification (`tamperedVerifies: false`). For AES-256-GCM, encrypting
`plaintextHex` under `key`/`nonce`/`aad` must yield `ciphertext` + `tag`.

**In CI:** `pnpm crypto:vectors:check` (wired into `ci:api`) regenerates in
memory and byte-compares against the committed JSON, failing on any drift. The
Node-version string in the file is ignored by the check, since it legitimately
varies across runners.

**Regenerate:** `node scripts/crypto-test-vectors.mjs` (only when intentionally
adding/altering vectors — review the diff).

## Scope and limits

- These are **primitive-level** KATs. They prove the building blocks are
  correct; they do **not** by themselves validate VEIL's protocol-level
  construction (Double Ratchet chaining, the `veil-frame-aad-v3` header binding,
  session bootstrap). Protocol-level interop is covered separately by the
  fixture contract in [`crypto-interoperability-fixtures.md`](crypto-interoperability-fixtures.md)
  and the envelope construction in [`crypto-envelope-spec.md`](crypto-envelope-spec.md).
- Adding protocol-level KATs (full ratchet step vectors, envelope
  encrypt/decrypt round-trips with pinned keys) is a natural follow-up once the
  adapter can export them deterministically.
