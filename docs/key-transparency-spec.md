# VEIL — Key Transparency Spec

Status: **design proposal** for external-audit review. No code yet.

Companion docs: [`threat-model.md`](threat-model.md),
[`crypto-envelope-spec.md`](crypto-envelope-spec.md),
[`security-hardening-roadmap.md`](security-hardening-roadmap.md) (item C).

## 1. The gap today

When Alice messages `@bob`, her client calls `getKeyBundle('@bob')` and
trusts the `identityPublicKey` the server returns. A malicious or
compromised server can return **its own** key for `@bob`, sit in the
middle, and read everything — classic key-substitution MITM. Nothing in the
protocol detects it automatically.

VEIL already has **safety numbers** (`safety_numbers.dart`, 60-digit,
derived from both identity keys) — but they only help if Alice and Bob
*manually* compare them out of band. Almost nobody does. Key transparency
makes detection **automatic**: the server is held to a single,
publicly-verifiable, append-only record of every `handle → identity key`
binding, so it cannot show Alice a key it can't also prove it showed
everyone else.

## 2. Goal

A client can verify that the identity key it received for a handle is:
1. **included** in a global append-only log (membership proof), and
2. **consistent** with the log it saw before (append-only proof — no
   silent rewrites), and
3. **the same** key every other observer sees (no split view).

If the server ever serves a forged or forked key, honest clients/monitors
detect it. The server's dishonesty becomes *evidence*, not a silent
compromise.

## 3. Mechanism (CONIKS / Signal-KT / Parakeet family)

- **Verifiable log.** The server maintains an append-only Merkle structure
  mapping `handle → (identity key, version)`. Each epoch it publishes a
  **signed tree head (STH)**: a root hash + epoch + signature.
- **Inclusion proof.** `getKeyBundle` returns, alongside the key, a Merkle
  inclusion proof that `(handle → key)` is in the tree under the current
  STH. The client verifies the proof before using the key.
- **Consistency proof.** Clients remember the last STH they saw; on each new
  STH they verify an append-only consistency proof (old tree is a prefix of
  new tree) — the server cannot retroactively change a past binding.
- **Split-view detection.** A server could still sign *different* STHs for
  different victims. Defeat it by **gossiping STHs**: clients cross-check
  STHs with each other and/or independent **monitors/auditors** that mirror
  the log. A fork means two STHs for the same epoch signed by the server —
  undeniable proof of misbehavior.
- **Handle privacy (VRF).** A naive log leaks the list of all handles.
  CONIKS-style designs key the tree by a **VRF(handle)** so the log is
  verifiable without being enumerable — preserves VEIL's no-directory
  posture.
- **First-contact pinning (TOFU+KT).** On first contact the client pins the
  KT-verified key; a later change surfaces as a **"safety number changed"**
  event tied to a verifiable log entry, not just a local heuristic.

## 4. VEIL integration sketch

- `getKeyBundle` response gains `{ inclusionProof, sth }`. The key is
  rejected if the proof doesn't verify against a trusted STH.
- New endpoints: `GET /kt/sth` (latest signed tree head), `GET /kt/proof`
  (inclusion + consistency proofs), `GET /kt/consistency?from=&to=`.
- Identity registration (`auth` / device publish) appends the binding and
  advances the epoch.
- Client stores the last trusted STH; ships with (or fetches) the list of
  independent monitors to gossip with.
- Ties into existing **safety numbers**: a KT-verified key-change is what
  the UI surfaces, replacing "trust me" with "here's the logged, signed
  change."

## 5. Hard parts (for audit / scoping)

- **The log is infrastructure**, with its own availability, signing-key
  custody (an HSM-held STH signing key separate from the app server), and
  monitor ecosystem. This is the bulk of the work, not the client proofs.
- **Bootstrapping trust** in the STH signing key (ship it pinned; rotation
  policy).
- **Monitors**: at least one independent monitor must exist for split-view
  detection to mean anything; document who runs it (the OTF/community angle
  fits — third parties can run monitors precisely because VEIL is open).
- **Privacy of the log** (VRF) and the epoch cadence vs. latency trade-off.

## 6. Honest limits

- KT detects key substitution; it does **not** stop a one-time active MITM
  before the victim's client has any trusted STH (mitigated by shipping a
  pinned genesis STH and TOFU pinning).
- It needs the monitor ecosystem to be real — a log nobody audits is
  theater. Don't claim KT protection until at least one independent monitor
  runs.
- It is orthogonal to message metadata (see `sealed-sender-spec.md`) and to
  PQ (`post-quantum-migration-spec.md`); KT secures *which key*, not who-
  talks-to-whom or future-quantum confidentiality.

## 7. Next steps

- [ ] Audit review of the log design + STH signing-key custody.
- [ ] Decide the Merkle structure (CONIKS-style prefix tree vs. an
      append-only transparency log with a separate index) and the VRF.
- [ ] Spec the `/kt/*` endpoints + the `getKeyBundle` proof fields in the
      API contracts.
- [ ] Stand up a reference monitor; document how third parties run one.
