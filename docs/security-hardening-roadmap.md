# VEIL — Security Hardening Roadmap

A grounded assessment of VEIL's current security stack (from a capability
scan of the codebase) and a prioritized list of what to add next. The goal
is to push the security posture toward — and past — Signal-grade, without
overstating what's already there.

## 1. Current posture (measured, not aspirational)

A row whose evidence only says where the code lives shows that the code
exists, not that a test or a device run backs it.

| Capability | State | Evidence |
| --- | --- | --- |
| E2E (X25519 + AES-256-GCM + Ed25519, Double Ratchet) | ✅ strong | `lib_crypto_adapter.dart`, `crypto-envelope-spec.md` |
| No backup / no recovery / device-bound identity | ✅ strong | enforced by `policy-check.mjs` (routes, modules, schema models, contracts, mobile backup code) |
| No plaintext message content on the server | ✅ CI-enforced | `schema-privacy-check.mjs`, [`server-data-inventory.md`](server-data-inventory.md); group and channel names and descriptions and device labels are still readable and are the gate's only allowlisted fields |
| Public claims backed by tests | ✅ CI-enforced | `claims-check.mjs`, [`claims.yaml`](claims.yaml) |
| Store privacy labels declare what the server stores | ✅ CI-enforced | `store-label-check.mjs` ties `store/appstore/app-privacy-answers.md` and `store/play/data-safety-answers.md` to the schema and to each other, and fails on any document that contradicts them |
| TLS pinning | ✅ present | `buildPinnedHttpClient` in `pinned_http_client.dart`, tested against a real TLS handshake in `pinned_tls_handshake_test.dart` |
| Hardware-isolated keys (Secure Enclave / StrongBox) | ❌ absent | keys sit in OS secure storage (Keychain / Keystore-encrypted preferences), not in a hardware key store |
| Screen-capture / preview protection | ⚠️ code present, untested | Android `FLAG_SECURE` in `MainActivity.kt`, the iOS app-switcher shield in `SceneDelegate.swift`, read through `platform_security_service.dart`; CI builds neither native app, no test exercises this code, and the repository records no device test of it |
| Integrity / jailbreak-root detection | ⚠️ code present, untested | root and jailbreak heuristics in `MainActivity.kt` and `AppDelegate.swift`; CI builds neither native app, no test exercises this code, and the repository records no device test of it |
| Disappearing messages | ✅ present | the server deletes a message once its `expiresAt` passes (`retention.service.ts`, `retention.service.spec.ts`); mobile drops it locally on time (`disappearing_messages_service.dart`, `disappearing_messages_service_test.dart`) |
| View-once messages | ⚠️ server only | the API deletes a view-once message when its recipient reads it (`messages.service.ts`, `messages.service.spec.ts`), but neither client sends one yet |
| Safety numbers (manual key verification) | ✅ present | `safety_numbers.dart` — 60-digit, Signal-style |
| Rate limiting / abuse throttle | ✅ present | the global `CfThrottlerGuard` with per-route `@Throttle` limits, counted in Redis when `VEIL_REDIS_URL` is set (required in production) and failing open while Redis is unreachable (`cf-throttler.guard.spec.ts`, `redis-throttler.storage.spec.ts`) |
| Push payloads metadata-minimal | ✅ present | `threat-model.md` |
| Message-length padding | ✅ shipped (mobile and web) | every message is ISO/IEC 7816-4 padded to a size bucket before AES-GCM, attachments to a Padmé length: `message_padding.dart` (1:1 and Sender Keys groups), web `padding.js`; pinned by the protocol-v2 known-answer vectors (`crypto-test-vectors.mjs`, `kat-v2.test.js`) |
| **Key zeroization** | ⚠️ weak | collection `.clear()` only; no true secret wiping (Dart GC/strings) |
| **Reproducible builds** | ❌ absent | no `SOURCE_DATE_EPOCH` / verifiable build; "open source" is currently unverifiable against the published APK |
| **Key transparency** | ❌ absent | safety numbers are manual; nothing auto-detects a malicious server swapping keys. Deleted handles are quarantined for 90 days, so a re-registered handle cannot pass as its old owner right away |
| **Duress / panic mode** | ❌ absent | no decoy unlock / panic wipe |
| Post-quantum | 📝 specced (#6/#7) | `post-quantum-migration-spec.md` |
| Sealed sender (metadata) | 📝 under revision | [`sealed-sender-design.md`](sealed-sender-design.md): the current design does not hide the sender |

## 2. Prioritized additions

Ranked by (security value × fit) and split by whether the work is gated on
an external crypto audit.

### Tier 1 — ship-able now, high trust value, NOT audit-gated

**A. Reproducible builds + binary transparency.**
For an AGPL security app this is foundational: today nobody can prove the
Play Store APK was built from the public source — so "open source and
auditable" is only half true. Make the Android build deterministic
(`SOURCE_DATE_EPOCH`, pinned toolchain/NDK, stripped non-determinism),
publish build instructions + expected hashes, and ideally a verification CI
job. This is build tooling, not crypto — no audit dependency — and it
upgrades the entire "trust us → verify us" story that everything else leans
on.

**B. Message-length padding — shipped.**
Protocol v2 pads every message on both clients before AES-GCM: ISO/IEC
7816-4 to the smallest bucket of 256 B, 512 B, … 64 KiB that fits, then
multiples of 64 KiB, and attachments to a Padmé length
(`crypto-envelope-spec.md` § Inner payload and § Attachments). A
ciphertext's size reveals only its bucket. Timing and volume stay visible;
padding does not hide them.

### Tier 2 — high value, larger / audit-adjacent

**C. Key transparency.**
The big one. Safety numbers exist but require both users to *manually*
compare — almost nobody does. Key transparency (an append-only,
publicly-verifiable log of identity-key→user bindings, CONIKS / Parakeet /
Signal-KT style) lets clients *automatically* detect a server that serves a
forged key, closing the last server-trust hole (active MITM via key
substitution). Significant design + ops (the log is infrastructure); spec
first, audit-gated.

**D. Hardened key zeroization.**
Move sensitive key material to `Uint8List` with explicit wipe-after-use and
native zeroization at the FFI boundary; avoid `String` for secrets (Dart
strings are immutable and GC'd, can't be wiped). Tightens the
post-compromise story. Medium effort, crypto-review touch.

### Tier 3 — feature-shaped, situational

**E. Duress / panic mode.** Decoy PIN → fake inbox; panic gesture →
local wipe. High impact for at-risk users (the Korea GTM's primary
segments), but safety-critical UX that must be designed carefully and
audited — a wrong "wipe" or a leaky decoy gets people hurt.

## 3. Recommendation

1. **Reproducible builds (A)** first — it's not audit-gated, it's the trust
   substrate the whole open-source/auditable pitch depends on, and it's
   shippable now.
2. **Key transparency (C)** as the flagship Tier-2 spec — it's the one
   capability that would put VEIL's server-trust model *ahead* of most
   messengers.

Protocol v2, its web port, message padding and Sender Keys shipped in
default builds before any external audit. The crypto-heavy items still open
(C, D, post-quantum, sealed sender) wait for the audit; build work (A) can
proceed in parallel now.

## 4. Honest framing

VEIL is already genuinely strong — the ratchet, no-recovery, a server that
stores no plaintext message content, message padding and manual key
verification are all real and measured above. Screen-capture protection and
integrity detection are code that no CI build or test exercises yet. The
server does still store group and channel names and descriptions and device
labels in readable form until their encryption ships. The gaps are the *next
tier* (verifiable builds, server-key-substitution resistance, and the timing
and volume that size padding does not hide), i.e. moving from "we encrypt
your content and minimize data" to "you don't have to trust our build, our
server's key honesty, or our traffic not leaking shape." Don't claim these
until they ship.
