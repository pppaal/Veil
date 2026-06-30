# VEIL — Post-Quantum Migration Spec (hybrid ML-KEM + X25519)

Status: **design proposal** for external-audit review. No code yet — this
document fixes the algorithm choices, hybrid construction, wire/version
changes, and rollout so the work can be scoped and audited before
implementation.

Companion docs: [`crypto-envelope-spec.md`](crypto-envelope-spec.md),
[`crypto-adapter-architecture.md`](crypto-adapter-architecture.md),
[`audited-crypto-library-decision.md`](audited-crypto-library-decision.md),
[`threat-model.md`](threat-model.md).

## 1. Why, and why now

The threat is **harvest-now-decrypt-later (HNDL)**: an adversary records
today's X25519-protected traffic and decrypts it once a cryptographically
relevant quantum computer (CRQC) exists. For a privacy messenger whose
whole promise is "no one but the recipient reads this," messages must stay
confidential for *decades*, so HNDL is the relevant horizon — not the
arrival date of a CRQC.

VEIL is **pre-1.0**. Signal (PQXDH → Triple Ratchet/SPQR) and Apple
(iMessage PQ3) are retrofitting PQ onto installed bases with migration
overhead. VEIL can ship **post-quantum by default from the first public
build** — a "born post-quantum" messenger — which is both the strongest
differentiator and the cheapest time to do it (no legacy sessions to
migrate).

## 2. Scope — what gets PQ, what doesn't

| Layer | Today | Change | Rationale |
| --- | --- | --- | --- |
| Initial key agreement (X3DH-equivalent) | X25519 | **Hybrid X25519 + ML-KEM-768** | This is the HNDL-critical step — the long-term secret a recorder wants. |
| DH ratchet (per-session forward secrecy) | X25519 | **Phase 2:** sparse PQ ratchet (SPQR-style) | Re-establishes PQ secrecy after compromise; heavier, so staged. |
| Per-message AEAD | AES-256-GCM | unchanged | 256-bit symmetric keys retain ~128-bit security under Grover; already PQ-adequate. |
| Identity / signatures | Ed25519 | unchanged for v3 (revisit ML-DSA later) | Signatures have **no HNDL risk** — a forgery must happen *before* a CRQC exists, not retroactively. Lower priority. |
| Attachment key wrap | x25519-aes256gcm | inherits hybrid KEM from the session | Same HNDL exposure as messages. |

Principle: **add PQ where recording-then-decrypting later breaks the
promise; leave the rest** until the libraries and standards settle.

## 3. Algorithm choice

- **KEM: ML-KEM-768** (FIPS 203, the Kyber standard). 768 parameter set
  targets NIST Level 3 — the balance Signal and Apple both chose.
- **Hybrid, never PQ-alone.** Combine with X25519 so the result is at
  least as strong as today even if ML-KEM is later weakened. This matches
  PQXDH and PQ3; PQ libraries are young and must not be a single point of
  failure.
- **Signatures stay Ed25519** for v3 (see scope table). A later v4 may add
  ML-DSA (FIPS 204) for identity keys if the audit recommends it.

### Hybrid construction (concatenation KEM)

```
(ek_x, dk_x)   = X25519 keypair          # ephemeral, as today
(ct_k, ss_k)   = ML-KEM-768.Encaps(pk_mlkem_recipient)
ss_x           = X25519(ek_x, pk_x_recipient)
root_secret    = HKDF-SHA256(
                   ikm  = ss_x || ss_k,            # order fixed: classical first
                   salt = 0,
                   info = "veil-pq-v3" || transcript_hash )
```

`transcript_hash` binds both public keys, both ciphertexts, and the
identity keys so neither component can be stripped or swapped (KEM
re-encapsulation / downgrade resistance). The combiner is a single
HKDF over the concatenated secrets — the construction Signal and Apple
both use — so security reduces to "X25519 OR ML-KEM holds," not "AND".

## 4. Prekey bundle & wire changes

Recipients publish an **ML-KEM prekey** alongside the existing X25519
prekeys. Size implications (the main cost):

| Item | X25519 | ML-KEM-768 |
| --- | --- | --- |
| Public key / prekey | 32 B | ~1184 B |
| KEM ciphertext (per handshake) | — (DH) | ~1088 B |

→ Prekey bundles and the first message grow by ~1–2 KB. Acceptable; note
it in storage/bandwidth budgets and the prekey-replenishment logic.

Versioning (per `crypto-envelope-spec.md` conventions):

- Adapter id: `lib-x25519-aes256gcm-v3` → **`lib-mlkem768-x25519-aes256gcm-v3`**
- Envelope version: `veil-envelope-v1` → **`veil-envelope-v2`** (add to
  `SUPPORTED_ENVELOPE_VERSIONS` in `packages/shared/src/domain/protocol.ts`)
- Session schema version: `2` → `3`
- Attachment algorithm hint: `x25519-aes256gcm` → `mlkem768-x25519-aes256gcm`

The envelope layout gains an ML-KEM ciphertext field in the handshake
header; steady-state ratchet messages are unchanged in Phase 1.

## 5. Implementation path (libraries)

Dart/Flutter has **no audit-grade ML-KEM** implementation. This aligns
with the existing decision (`audited-crypto-library-decision.md`) to keep
audited primitives in native code:

- Implement ML-KEM-768 in **native code via FFI** — RustCrypto `ml-kem`
  or `liboqs` (`liboqs-rust`), behind the existing `CryptoAdapter`
  abstraction so Dart only calls `encaps`/`decaps`/`keygen`.
- Keep X25519/AES-GCM/Ed25519/HKDF exactly as the v2 adapter has them; the
  v3 adapter *wraps* v2 and adds the KEM leg + combiner.
- Constant-time and zeroization requirements transfer to the native layer;
  fold into the audit scope.

Phasing:
- **Phase 1 — PQXDH-equivalent.** Hybrid only at the initial handshake.
  Smaller, fully protects HNDL for session establishment. Ship this first.
- **Phase 2 — SPQR-equivalent.** Add a sparse PQ ratchet so post-compromise
  security is also PQ. Heavier (periodic ML-KEM in the ratchet); ship after
  Phase 1 is audited and stable.

## 6. Rollout

1. New v3 adapter behind a capability flag; advertise supported envelope
   versions in the prekey bundle.
2. **Born-PQ default:** because VEIL is pre-launch, new installs negotiate
   v3 by default. v1/v2 stay in `SUPPORTED_ENVELOPE_VERSIONS` only for
   interop fixtures / any internal alpha sessions, then can be dropped
   before GA — no public migration debt.
3. Interop fixtures (`crypto-interoperability-fixtures.md`) gain v3 vectors
   so re-implementers and auditors can verify the combiner.
4. `VEIL_AUDITED_CRYPTO_ATTESTED` (the production boot gate) is only set
   after the v3 hybrid is in the external-audit scope and signed off.

## 7. Risks & honest limits

- **PQ libraries are young.** Hybrid (not PQ-alone) is the mitigation: a
  break in ML-KEM degrades to today's X25519 security, not to zero.
- **Size.** ~1–2 KB per handshake/prekey; monitor prekey storage and the
  first-message path on mobile networks.
- **Signatures deferred.** Identity stays Ed25519 in v3 by design (no HNDL
  risk). Revisit ML-DSA only if the audit calls for it.
- **Not a weekend feature.** This is real crypto: native ML-KEM, a new
  combiner, transcript binding, downgrade resistance, and an audit pass.
  The value of *this* document is locking the design before that spend.

## 8. Next steps

- [ ] Audit firm to review this design (fold into the OTF / external-audit
      scope already in `external-audit-firm-shortlist.md`).
- [ ] Prototype native ML-KEM-768 keygen/encaps/decaps over FFI; benchmark
      on a low-end Android device.
- [ ] Draft the v3 envelope layout delta in `crypto-envelope-spec.md`.
- [ ] Add v3 interop test vectors.
