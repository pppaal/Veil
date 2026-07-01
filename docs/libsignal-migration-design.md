# libsignal migration — design

## Status

**Design-only. Decision + device work required.** This document plans moving
VEIL's 1:1 message crypto from the in-house adapter to Signal's own library, so
the protocol core is code that has already been externally audited and
battle-tested rather than a solo re-implementation.

## Why

Today the ratchet, key agreement, and AEAD framing are a VEIL-authored Dart
implementation on top of the pure-Dart `cryptography` package
(`lib_crypto_adapter.dart`, adapter id `lib-x25519-aes256gcm-v3`). It is
CI-tested and has AEAD header binding (v3), but:

- an external audit would have to cover the **entire** crypto implementation,
  not just the integration — the most expensive kind of audit;
- implementation bugs (ratchet state, nonce handling, key derivation, memory
  hygiene) are exactly where real-world E2E systems fail, and a single-author
  re-implementation carries that risk by construction.

Adopting Signal's library moves the protocol core to audited code and shrinks
VEIL's own audit surface to the **integration layer** (how we call it, where we
store keys, session lifecycle).

## The seam already exists

The swap point is clean and already in place:

- `MessageCryptoEngine` (abstract, `crypto_engine.dart`) — the interface every
  call site uses.
- `CryptoAdapter.adapterId` — a version marker carried so peers/records know
  which engine produced a session/envelope.
- `crypto_adapter_registry.dart` — the single factory that selects the active
  adapter (currently hard-wired to the lib adapter).
- Existing implementations: `_LibMessageCryptoEngine` (homegrown) and
  `_MockMessageCryptoEngine` (dev/test).

A Signal-backed engine is therefore a **third `MessageCryptoEngine`
implementation** plus a registry change — no message/session call site changes.

## Two candidate targets (decision required)

### Option A — official libsignal (Rust core via FFI)  ← matches the goal

`libsignal` (signalapp) is a Rust core with first-class Java / Swift / Node
bindings. It is the actually-audited artifact.

- **Pro:** inherits the audited protocol core; audit shrinks to integration.
- **Con:** **no official Dart/Flutter binding.** Flutter adoption means
  cross-compiling the Rust core to `.so` (Android, via NDK/JNI) and a static
  lib / xcframework (iOS), generating Dart FFI bindings (`ffigen`), and wiring
  platform loading. This requires a real device/native toolchain —
  **not buildable or testable in the current CI-only, no-Flutter-SDK
  environment.**

### Option B — `libsignal_protocol_dart` (pure-Dart port)

A third-party pure-Dart implementation of the Signal Protocol (MixinNetwork,
used by Mixin Messenger).

- **Pro:** no native build — addable via `pubspec.yaml`, wireable in Dart,
  `flutter analyze` + `flutter test` in CI. Far more widely exercised than a
  solo implementation.
- **Con:** it is a **Dart re-implementation, not the audited Rust core.** It
  does **not** deliver the "inherit the audit / shrink audit scope" benefit —
  it would itself need review. It is a code-quality/maturity upgrade, not an
  audit upgrade.

**Recommendation:** if the driver is audit-inheritance (it is), **Option A** is
the only one that delivers it. Option B is a reasonable interim if the priority
were shipping over audit scope, but it does not change the audit story.

## Migration plan (Option A)

Phased so nothing breaks mid-flight; the registry + `adapterId` make old and
new engines coexist.

**Phase L.1 — seam freeze + interop spec (CI-safe, doable now)**
- Freeze the `MessageCryptoEngine` surface the Signal engine must satisfy.
- Write the envelope/interop spec: new sessions get a new `adapterId`
  (e.g. `signal-libsignal-v1`) and, if needed, a new envelope version marker
  alongside `veil-envelope-v1`; the existing lib decrypt path stays for
  backward compatibility during the transition window.

**Phase L.2 — native artifacts (device / native toolchain)**
- Vendor/pin a `libsignal` version; build Rust → Android `.so` (arm64,
  armeabi-v7a, x86_64) and iOS xcframework. Reproducible build script in CI
  once a native runner is available.

**Phase L.3 — FFI bindings + engine (device)**
- `ffigen` over the C API; implement `SignalMessageCryptoEngine implements
  MessageCryptoEngine`.
- Back the identity / session / prekey stores with `SecureStorageService` +
  `drift`, matching libsignal's store traits.

**Phase L.4 — X3DH prekeys (bonus, closes a current residual risk)**
- libsignal brings real X3DH one-time prekeys, removing today's "first message
  lacks forward secrecy" gap. Wire the prekey publish/replenish endpoints.

**Phase L.5 — dual-run + cutover**
- Run both engines against shared test vectors; enable Signal engine for new
  sessions behind a flag; migrate; then remove `_LibMessageCryptoEngine` once
  no live sessions use it.

**Phase L.6 — integration audit**
- External review of the integration layer only (stores, session lifecycle,
  FFI boundary, memory hygiene) — much smaller/cheaper than a full-crypto audit.

## What can be done blind (now) vs. needs a device

| Work | Where |
|---|---|
| L.1 seam freeze + interop/envelope spec | now, CI-safe |
| Store-trait Dart scaffolding (no native calls) | now, `analyze`-able |
| L.2 native Rust cross-builds | device / native runner |
| L.3 FFI bindings + real engine | device |
| L.4 X3DH prekey server endpoints | now (server, CI-safe) — mobile wiring on device |
| L.5 dual-run E2E, cutover | device |

## Audit implication

- **Do not** commission a full external audit of `_LibMessageCryptoEngine` if
  Option A is chosen — auditing code that will be replaced is wasted spend.
- Decide A vs. B **before** any audit engagement, so the audit is scoped to the
  code that will actually ship.
