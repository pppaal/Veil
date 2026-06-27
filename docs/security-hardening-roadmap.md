# VEIL — Security Hardening Roadmap

A grounded assessment of VEIL's current security stack (from a capability
scan of the codebase) and a prioritized list of what to add next. The goal
is to push the security posture toward — and past — Signal-grade, without
overstating what's already there.

## 1. Current posture (measured, not aspirational)

| Capability | State | Evidence |
| --- | --- | --- |
| E2E (X25519 + AES-256-GCM + Ed25519, Double Ratchet) | ✅ strong | `lib_crypto_adapter.dart`, `crypto-envelope-spec.md` |
| No backup / no recovery / device-bound identity | ✅ strong | enforced by `policy-check.mjs` |
| TLS pinning | ✅ present | `buildPinnedHttpClient`, 5 files |
| Hardware-backed keys (Secure Enclave / StrongBox) | ✅ present | 28 files |
| Screen-capture / preview protection | ✅ present | `screenCaptureProtection`, 7 files |
| Integrity / jailbreak-root detection | ✅ present | `integrityCompromised`, 12 files |
| Disappearing / view-once messages | ✅ present | 100 files |
| Safety numbers (manual key verification) | ✅ present | `safety_numbers.dart` — 60-digit, Signal-style |
| Rate limiting / abuse throttle | ✅ present | `@Throttle`, 29 files |
| Push payloads metadata-minimal | ✅ present | `threat-model.md` |
| **Message-length padding** | ⚠️ **absent in prod** | only `padRight` in tests; ciphertext length ≈ plaintext length |
| **Key zeroization** | ⚠️ weak | collection `.clear()` only; no true secret wiping (Dart GC/strings) |
| **Reproducible builds** | ❌ absent | no `SOURCE_DATE_EPOCH` / verifiable build; "open source" is currently unverifiable against the published APK |
| **Key transparency** | ❌ absent | safety numbers are manual; nothing auto-detects a malicious server swapping keys |
| **Duress / panic mode** | ❌ absent | no decoy unlock / panic wipe |
| Post-quantum | 📝 specced (#6/#7) | `post-quantum-migration-spec.md` |
| Sealed sender (metadata) | 📝 specced (#8) | `sealed-sender-spec.md` |

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

**B. Message-length padding (traffic-analysis resistance).**
Confirmed gap: ciphertext length tracks plaintext length, so the server (or
a network observer) learns message sizes and can fingerprint content/
behavior even though it can't read it. Pad plaintext to length buckets
before GCM (Padmé, or fixed buckets e.g. 256/1k/4k/16k…). Small, local
change to the encrypt path + envelope spec; pairs directly with the sealed
sender / metadata track. Mild crypto-review touch, but not a redesign.

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
2. **Message-length padding (B)** next — a real, confirmed metadata leak
   with a contained fix that complements sealed sender.
3. **Key transparency (C)** as the flagship Tier-2 spec — it's the one
   capability that would put VEIL's server-trust model *ahead* of most
   messengers.

Crypto-heavy items (C, D, post-quantum, sealed sender) stay behind the
external audit; build/padding work (A, B) can proceed in parallel now.

## 4. Honest framing

VEIL is already genuinely strong — hardware keys, ratchet, no-recovery,
integrity detection, manual key verification are all real and measured
above. The gaps are the *next tier* (verifiable builds, traffic-shape and
server-key-substitution resistance), i.e. moving from "we encrypt your
content and minimize data" to "you don't have to trust our build, our
server's key honesty, or our traffic not leaking shape." Don't claim these
until they ship.
