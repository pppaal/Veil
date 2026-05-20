# Internal pre-audit — mobile crypto code review

**Reviewer:** Claude (AI assistant) — internal code review, NOT an
independent external audit.
**Scope:** `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart`
(1567 lines) — identity, envelope codec, Double Ratchet
encrypt/decrypt, DH steps, key derivation, skipped-key handling.
**Date:** 2026-05.

> ⚠️ **This is not a substitute for external audit.** It has no
> independence, no liability, no formal methods, no side-channel
> analysis, no fuzzing. Its only purpose is to catch obvious issues
> *before* paying for the real audit, so the external firm spends its
> (expensive) time on deep findings instead of surface ones. The
> production gate (`VEIL_AUDITED_CRYPTO_ATTESTED`) stays false
> regardless of this document.

## What's correct (verified by reading)

| # | Property | Evidence |
|---|---|---|
| G-1 | CSPRNG for nonces | `Random.secure()` (line 1034) used for all GCM nonces + content keys |
| G-2 | No (key, nonce) reuse | Each message derives a fresh `messageKey` from the chain at `counter`, then advances the chain. Per-key message count = 1, so the random 96-bit nonce can't collide under a fixed key |
| G-3 | Forward secrecy | `_advanceChainKey` is one-way HKDF; old chain key replaced each message |
| G-4 | Post-compromise security | `performSendDhStep` / `performReceiveDhStep` mix fresh ECDH into the root on every turn-flip |
| G-5 | Active-MITM defense | `_resolveRemoteX25519Key` mandates Ed25519 signature verification of the peer's X25519 prekey, **no silent downgrade** on missing/invalid sig |
| G-6 | Replay protection | `_resolveReceiveMessageKey` returns null for `counter < receiveCounter` (consumed) |
| G-7 | Skipped-key DoS caps | `_maxSkippedKeys` 1000 global, `_maxSkippedKeysPerEpoch` 200, 7-day TTL with lazy sweep |
| G-8 | Symmetric root KDF | `_kdfRootKey` derives 64 bytes via HKDF-SHA256, splits root/chain; both sides compute identical output from symmetric inputs |
| G-9 | Counter encoding | BE u32, explicit `_encodeCounter` / `_decodeCounter` |

The cryptographic design is sound and follows the Double Ratchet spec
faithfully. This is above-average implementation quality for a solo
project.

## Findings

### F-1 — No AEAD Associated Data (Medium)

`encryptMessage` calls:
```dart
final secretBox = await _aesGcm.encrypt(
  utf8.encode(payload),
  secretKey: messageKey,
  nonce: nonce,
);   // <-- no `aad:` parameter
```

The wire frame is `[ratchetPub(32)][counter(4)][ciphertext][mac(16)]`.
The GCM MAC authenticates only the encrypted payload + nonce. The
following are **not** cryptographically bound to the ciphertext:

- `ratchetPub` and `counter` (frame header, outside the GCM region)
- `conversationId`, `senderDeviceId`, `recipientUserId` (envelope
  routing fields)

**Impact (limited but real):**
- Tampering `ratchetPub` / `counter` causes wrong-key derivation →
  decryption fails. This is a DoS, not a forgery.
- Cross-conversation replay is blocked in practice because the session
  is keyed by `conversationId` and a different session derives a
  different key.
- But the envelope routing metadata is malleable. Defense-in-depth and
  the project's own `docs/envelope-v3-unified-spec.md` already
  prescribe AD binding.

**Recommendation:** pass `aad = conversationId || senderDeviceId ||
recipientUserId || ratchetPub || counterBytes` to both `encrypt` and
`decrypt`. This is exactly the v3 envelope AD construction; pulling it
forward into v2 is low-risk and closes the gap before audit. The
`cryptography` package's `AesGcm.encrypt` accepts an `aad` parameter.

**Status (2026-05):**
- ✅ **Web demo: applied + tested.** `apps/web-demo/lib/aad.js` is a
  pure, length-prefixed canonical AAD builder (7 Vitest cases incl.
  field-boundary confusion). Wired into `encryptForConv` /
  `decryptFromConv` binding `{conversationId, senderDeviceId}`.
  `recipientUserId` omitted (empty on group sends, not reliably present
  at every decrypt call site). conversationId was already bound via the
  HKDF `info`; the new value is senderDeviceId. Decrypt keeps a legacy
  no-AAD fallback so pre-F-1 cached messages still open during the
  transition.
- ⏳ **Mobile: patch specified below, NOT applied.** The Flutter SDK is
  not available in the dev sandbox, so the change cannot be unit-tested
  here. Applying untested edits to the most security-critical file is
  the exact "risky action without verification" to avoid. Apply on a
  machine with Flutter and run `pnpm mobile:test` (esp.
  `crypto_envelope_pinning_test.dart`, `crypto_round_trip_test.dart`,
  `dh_ratchet_test.dart`) before merge.

### Mobile patch (apply + test on a Flutter machine)

In `lib_crypto_adapter.dart`, build the AAD from the frame fields that
both sides already have, and pass it to GCM symmetrically.

```dart
// New helper near the other static crypto helpers:
static Uint8List _buildAad({
  required String conversationId,
  required String senderDeviceId,
  required List<int> ratchetPub,
  required List<int> counterBytes,
}) {
  final b = BytesBuilder();
  void field(List<int> bytes) {
    final len = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    b.add(len.buffer.asUint8List());
    b.add(bytes);
  }
  b.add(utf8.encode('veil-aad-v1'));
  field(utf8.encode(conversationId));
  field(utf8.encode(senderDeviceId));
  field(ratchetPub);
  field(counterBytes);
  return b.toBytes();
}
```

In `encryptMessage`, after computing `ratchetPub` and `counterBytes`:

```dart
final aad = _buildAad(
  conversationId: conversationId,
  senderDeviceId: senderDeviceId,
  ratchetPub: ratchetPub,
  counterBytes: counterBytes,
);
final secretBox = await _aesGcm.encrypt(
  utf8.encode(payload),
  secretKey: messageKey,
  nonce: nonce,
  aad: aad,                    // <-- add this
);
```

In `decryptMessage`, the receiver already parses `incomingPeerPub`
(== ratchetPub) and `counter`. Rebuild the same AAD before
`_aesGcm.decrypt`:

```dart
final counterBytes = ciphertextBytes.sublist(32, 36);
final aad = _buildAad(
  conversationId: envelope.conversationId,
  senderDeviceId: envelope.senderDeviceId,
  ratchetPub: incomingPeerPub,
  counterBytes: counterBytes,
);
final cleartext = await _aesGcm.decrypt(
  secretBox,
  secretKey: messageKey,
  aad: aad,                    // <-- add this
);
```

Wire-break note: this is NOT backward compatible — old envelopes
decrypt-fail under the new AAD. For a beta with no real persisted
history that's acceptable (decrypt returns the existing
`[Decryption failed]` sentinel, no crash). If a transition window is
needed, mirror the web demo's try-with-aad-then-without fallback.
Update `crypto_envelope_pinning_test.dart` fixtures to the new tag.

### F-2 — In-band sentinel plaintext on decryption failure (Low)

`decryptMessage` returns failures as a normal-looking
`DecryptedMessage` whose `body` is a sentinel string:
- `[Unable to decrypt: invalid envelope]`
- `[Session not established — sync required]`
- `[Replayed or out-of-window message]`
- `[Decryption failed]`

A genuine message whose body is literally `[Decryption failed]` is
indistinguishable from a real failure. Possible confusing UX or a
weak spoofing vector (an attacker sends a real message with that body
to fake a failure).

**Recommendation:** return a typed result (a `success`/`failure`
discriminated union or a nullable + error enum) instead of in-band
sentinels, and let the UI layer map failures to localized strings.

### F-3 — Bootstrap path not fully reviewed (Verify in audit)

The initial session bootstrap (`_LibSessionBootstrapper`,
inbound-bootstrap from a sender ephemeral) was only partially read.
The per-message ratchet pubs are intentionally unsigned (standard
Double Ratchet — the root key binds them), which is correct **only if**
the bootstrap root is derived from the signature-verified signed
prekey. G-5 confirms the prekey is verified; the external audit should
confirm the bootstrap wires that verified key into the root and that
the first inbound ephemeral cannot be substituted by the server.

### F-4 — Version string inconsistency (Informational)

Version tags differ across layers: `_envelopeVersion =
'veil-envelope-v1'`, `adapterId = 'lib-x25519-aes256gcm-v2'`, KDF info
`'veil-dh-rk-v2'`, message info `'veil-msg-v1'`. Not a security issue,
but the envelope-v3 migration must map these carefully so a v3 client
negotiating with a v2 client doesn't mis-key.

### F-5 — Key material lifetime in memory (Verify in audit)

`SecretKey` / `SimpleKeyPairData` are held as plain fields on
`_SessionState`. Dart doesn't expose reliable zeroization, and the
`cryptography` package's in-memory `SecretKey` keeps bytes on the heap.
A memory-dump adversary (rooted device, cold-boot) could recover live
session keys. This is largely inherent to managed-runtime crypto; the
audit should assess whether the threat model requires native secure
memory for the ratchet state (vs the current secure-storage-at-rest
approach, which IS in place via the snapshot persister).

## What I could NOT assess (limits of this review)

- Side-channel / timing leakage (needs runtime instrumentation)
- The `cryptography` Dart package's own correctness (trusted upstream)
- Formal protocol verification (needs ProVerif / Tamarin)
- Fuzzing of the envelope parser against malformed frames
- Concurrency / re-entrancy on the session state under parallel
  send/receive
- The full bootstrap + snapshot-restore migration chain
  (`_migrate*`)
- Whether `notifySessionChanged` debounce can drop the most-recent
  ratchet state on a crash within the 300ms window (correctness, not
  crypto)

## Priority for the external audit

Hand the auditor this list so they skip the surface and go deep:

1. **F-1 AD binding** — likely a real finding; consider fixing before
   audit to save a finding+retest cycle.
2. **F-3 bootstrap authentication** — the highest-value thing to verify
   formally (active MITM at session establishment).
3. **F-5 memory lifetime** — threat-model dependent.
4. Side-channels + formal verification — only an external firm can do
   these.

## Bottom line

The implementation is competent and follows the Double Ratchet
correctly. The one finding worth acting on pre-audit is **F-1 (AEAD
associated data)**. Everything else is either informational or
requires an external firm's tools. This review does **not** clear the
production gate — it just means the external audit will likely come
back with fewer surface findings.
