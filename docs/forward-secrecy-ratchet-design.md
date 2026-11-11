# Double Ratchet — Design (protocol v2)

## Goal

Give VEIL's 1:1 message encryption **forward secrecy** (compromise of current
state reveals no past messages), **post-compromise security** (compromise heals
after a reply turn) and **mutual authentication** (nobody, the server included,
can open a session as someone else), while staying correct under reordering,
concurrency and crashes.

The normative wire format is
[crypto-envelope-spec.md](crypto-envelope-spec.md) §"Protocol v2"; this
document explains the design. Code:
`apps/mobile/lib/src/core/crypto/` (`x3dh/`, `ratchet/`, `payload/`,
`attachment/`, adapted by `lib_crypto_adapter.dart`).

## History

- **Ratchet v1** — symmetric hash ratchet only (forward secrecy).
- **Ratchet v2 (`veil-envelope-v1` wire)** — added the DH ratchet and session
  persistence. Defects found by the 2026 audit, all reproduced: the responder
  authenticated nobody; a straggler from the previous turn was lost, and a
  stashed one triggered a bogus DH step that corrupted the session; concurrent
  decrypt/encrypt rolled state back (key reuse); debounced, single-blob
  persistence lost updates; simultaneous first messages broke the chat.
- **Protocol v2 (`veil-envelope-v2`)** — this design. Legacy sessions keep the
  old wire format for peers that still publish v1 bundles.

## Handshake: X3DH

Each device has an Ed25519 identity key `IK`, an X25519 identity key `IKx`
certified by `IK`, a signed prekey `SPK` (rotated, with a timestamp) and
one-time prekeys `OPK`. The initiator verifies the bundle, draws an ephemeral
`EK` and computes

```
SK = HKDF(0xFF*32 || DH(IKx_A, SPK_B) || DH(EK, IKx_B) || DH(EK, SPK_B) [|| DH(EK, OPK_B)], ...)
```

`DH(IKx_A, SPK_B)` is what authenticates the initiator: computing it needs
`IKx_A`'s private key. Its identity keys and `EK` ride in a PreKey header on
every frame until the responder replies, and the associated data
`AD = IKed_A || IKx_A || IKed_B || IKx_B` is bound into every frame's AAD.

The responder needs no explicit bootstrap: decrypting a PreKey frame looks up
the named SPK (current, or superseded within a 14-day grace) and OPK, verifies
the IKx certificate, mirrors the DHs, receives the frame, and only after the
AEAD verified asks the optional identity verifier (identity pinning, wired in a
later wave). The OPK private key is deleted after the new state is durable, so
a second handshake naming it fails closed.

## Ratchet

Signal's Double Ratchet:

- The initiator starts with a fresh ratchet key and a sending chain from
  `KDF_RK(SK, DH(DHs, SPK_B))`; the responder starts with `DHs = SPK_B`.
- Each header carries `(ratchetPub, PN, N)`. On a new `ratchetPub`, the
  receiver first stashes the keys `Nr..PN-1` of the chain the peer is leaving
  under the **old** key, then steps. A stashed key is always looked up before
  any DH step, so a straggler never touches the ratchet.
- A receive DH step arms the next send step; the send half of Signal's
  DHRatchet is deferred to that send (same keys, one less key pair per turn
  when the receiver stays silent).
- Caps: at most 200 keys stashed by one frame, 1000 per session (oldest
  evicted), 7-day lifetime. Ratchet keys the peer moved past are remembered so
  a frame naming one is classified as a replay without a DH attempt.

The root, chain and message KDFs are the v1 ones (`veil-dh-rk-v2`,
`veil-chain-next-v1`, `veil-msg-v1`); only what feeds them changed.

## State machine safety

- **Copy-on-write.** Every operation works on a deep copy of the state it
  touches. A failed AEAD, a replay or a persistence error discards the copy;
  nothing is ever restored "back", so a concurrent operation cannot be
  overwritten.
- **Per-conversation serial lock** around bootstrap, legacy inbound bootstrap,
  encrypt, decrypt, rekey and restore. Re-rendering one's own message while
  sending can no longer reuse a counter.
- **Durable before visible.** A commit awaits the persister and only then
  publishes the new state; encrypt returns ciphertext only after its state is
  on disk. There is no debounce; `flushPendingSnapshotWrites` just waits for
  writes in flight.
- **Zeroization.** The losing side of every commit (the superseded state or
  the failed copy) has its root, chain, ratchet-private and skipped-key buffers
  overwritten, and intermediate chain keys are wiped as the chain advances.
  Best effort: Dart cannot reach copies the GC or package internals made.

## Session records and glare

A conversation holds a record: the current state plus up to five archived
states (30 days). Re-bootstrapping archives instead of destroying, so messages
already in flight on the old state still decrypt. Normal frames try the current
state, then the archived ones.

Glare (both peers initiate before either hears back): each side installs the
other's state from its PreKey frame; the state initiated by the lexicographically
lower identity key becomes the sending state on both sides, and the other stays
decryptable. A locally initiated state that already received something is
replaced by a peer's new PreKey frame (the peer evidently reset).

## Attachments

Each blob gets a random AES-256-GCM key and nonce, Padmé padding and an AAD
bound to its attachment id. The key, nonce, digest, size and type travel only
inside the ratchet payload, so attachments inherit the session's forward
secrecy and work for groups without per-member wrapping. The outer envelope
carries just the attachment id; receivers never trust outer attachment fields.

## Persistence

Snapshot schema v4 `{v: 4, rev, current, archived[]}` is stored per
conversation (`veil.crypto.session.<sha256hex(id)>` plus an index) through one
serial write queue that drops a write whose `rev` is older than the stored one.
See [crypto-session-state-migration.md](crypto-session-state-migration.md).

## Tests

- `test/crypto/x3dh_v2_test.dart` — forged initiator, fingerprints, verifier
  veto, OPK single use, SPK rotation grace and pruning, bundle signatures and
  freshness, v1 identity upgrade, the C1 bundle vector.
- `test/crypto/dh_ratchet_reorder_test.dart` — audit scenarios S1/S2, 20 seeded
  shuffles with delays across turn flips, replay classification.
- `test/crypto/ratchet_concurrency_test.dart` — audit S3, fuzzed interleaving,
  encrypt waits for the persister.
- `test/crypto/session_record_glare_test.dart` — glare convergence and lossless
  re-bootstrap.
- `test/crypto/session_snapshot_v4_test.dart`,
  `test/crypto/secure_storage_session_snapshot_test.dart` — snapshot schema,
  v2/v3 restore, rev ordering, slow concurrent storage, legacy blob migration.
- `test/crypto/crypto_kat_v2_test.dart` — byte-for-byte replay of the Node
  reference vectors.
- `test/dh_ratchet_test.dart`, `test/session_rekey_test.dart`,
  `test/crypto_zeroization_test.dart` and the other `test/crypto_*` suites.

## Security properties summary

| Property | ratchet v2 (`veil-envelope-v1`) | protocol v2 |
|---|---|---|
| Forward secrecy (per message) | ✅ | ✅ |
| Post-compromise security | ✅ | ✅ |
| Initiator authenticated | ❌ | ✅ DH(IKx_A, SPK_B) |
| One-time prekeys | ❌ | ✅ consumed once |
| Out-of-order across DH steps | ❌ lost or corrupting | ✅ PN stash |
| Concurrency / crash safety | ❌ rollback, debounced writes | ✅ lock, copy-on-write, durable commits |
| Glare | ❌ broken chat | ✅ converges |
| Attachments forward secret | ❌ wrapped to static key | ✅ key inside the ratchet |
| Typed decrypt results | ❌ placeholder bodies | ✅ `DecryptStatus` |

## Deferred

- libsignal (PQXDH + SPQR) as the default engine; this Dart protocol remains
  the default build and the web interop reference until then.
- Identity pinning (the verifier hook) and key transparency.
- Prekey publication and SPK rotation scheduling in the app (the
  `PrekeyManager` capability exists; wiring it to the key directory comes with
  the directory client).
