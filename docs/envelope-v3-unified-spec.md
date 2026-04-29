# Envelope v3 — unified wire format spec

## Status

Design draft. **Not implemented**. External crypto review required before
merge.

## Why v3

Today VEIL has two parallel envelope dialects:

- **Mobile (Flutter / `LibCryptoAdapter`)**: full Signal-style double
  ratchet. Wire = `[senderRatchetPub:32][counter:u32 BE][AEAD ct]`. Has
  forward secrecy + post-compromise security + skipped-key handling. Spec
  in `docs/forward-secrecy-ratchet-design.md`.
- **Web demo**: single-shot ECDH-per-message. Wire = `"v2." +
  b64u(AES-GCM ct)` plus a separate `nonce` field. Forward secrecy
  per-message via fresh nonce, no post-compromise — a stolen X25519
  identity key decrypts every past and future message until the user
  rotates the handle.

This means a mobile user messaging a web user falls back to the weaker
property set, and the server has to accept both shapes. v3 unifies on a
single envelope that both clients speak.

## Goals

1. Single wire format for web + mobile + future native ports
2. Forward secrecy + post-compromise security on both ends
3. Backward-compatible read of v2 envelopes during a transition window
4. No handshake round-trip on first contact
5. Server stays ciphertext-only; no protocol fields require parsing

## Non-goals

- Sealed sender / metadata reduction (separate work)
- Multi-device fan-out crypto (separate work)
- Group ratchet (Signal Sender Keys equivalent — separate work)

## Wire format

```
envelope.version    = "veil-envelope-v3"            // string in DTO
envelope.ciphertext = "v3." + b64u(payload)          // payload format below
envelope.nonce      = b64u(nonce)                    // 12 random bytes per message
```

`payload` (binary, before base64url):

```
+--------+---------------------+----------+--------------+
| 0x03   | senderRatchetPub:32 | ctr:u32  | AEAD ct + tag |
+--------+---------------------+----------+--------------+
```

- Version byte `0x03` so a future v4 can flip without re-versioning the
  string field. Decoders MUST reject any other byte.
- `senderRatchetPub`: rotating X25519 pub of the sender. Mobile's existing
  format already has this; web gains it.
- `ctr`: BE u32 send-chain counter. Resets to 0 on every send-side DH step.
- `AEAD ct + tag`: AES-256-GCM(messageKey, nonce, plaintext, AD). The
  GCM tag (16 bytes) is appended to ciphertext per the WebCrypto and
  RustCrypto idiom.

`nonce` stays in the existing `envelope.nonce` field (separate from the
payload) so the server-side `nonce` regex (`^[A-Za-z0-9._:-]{1,512}$`)
keeps validating.

`AD` (Additional Data, AEAD-bound, NOT on wire):

```
AD = "veil-envelope-v3"
   | conversationId
   | senderDeviceId
   | recipientUserId-or-empty
   | senderRatchetPub
   | ctr (4 bytes BE)
```

This binds every envelope field that should be tamper-evident. The
server's existing DTO validation (UUIDs, base64, length caps) still runs
unchanged.

## Key derivation (chains)

Initial bootstrap from the existing X25519 identity ECDH:

```
IK_alice, IK_bob   // X25519 identity privates (existing)
sharedSecret = X25519(IK_alice_priv, IK_bob_pub)
              = X25519(IK_bob_priv,   IK_alice_pub)

rootKey  = HKDF-SHA256(sharedSecret, salt=conversationId,
                       info="veil-root-v3", L=32)
chainA   = HKDF-SHA256(sharedSecret, salt=conversationId,
                       info="veil-chain-A-v3", L=32)
chainB   = HKDF-SHA256(sharedSecret, salt=conversationId,
                       info="veil-chain-B-v3", L=32)
```

The peer with the lexicographically smaller `senderDeviceId` (UUID-as-
string compare) takes `chainA` as its initial send chain; the other
mirrors. This matches the current mobile rule.

Per-message:

```
messageKey = HKDF-SHA256(chainKey_n, salt=ctr-bytes,
                         info="veil-msg-v3", L=32)
chainKey_{n+1} = HKDF-SHA256(chainKey_n, salt=[0x01],
                              info="veil-chain-step-v3", L=32)
```

DH ratchet step (send side, runs at start of `encrypt` if
`hasReceivedSinceLastSend`):

```
newPriv, newPub = X25519.generateKeypair()
dh = X25519(newPriv, lastSeenPeerRatchetPub)
(rootKey', sendChainKey') = HKDF-SHA256(dh, salt=rootKey,
                                        info="veil-dh-rk-v3", L=64).split(32, 32)
sendCounter = 0
swap sendRatchetPriv <- newPriv, sendRatchetPub <- newPub
clear hasReceivedSinceLastSend
```

DH receive step is symmetric, gated on `incomingPeerPub !=
lastSeenPeerRatchetPub`.

## Migration: v2 → v3

### Phase W.1 — server-side dual accept (no client change)

Server already accepts arbitrary version strings via
`SUPPORTED_ENVELOPE_VERSIONS`. Add `"veil-envelope-v3"` to the
shared/protocol constants but ship no client implementation yet. Goal:
no behavior change, just permission to receive v3 once clients send it.

### Phase W.2 — web demo writes v3, reads both

Implement v3 send + receive in `apps/web-demo/app.js`. While reading,
inspect the `version` field:

- `"veil-envelope-v3"` → v3 path (parse 0x03 prefix, run ratchet)
- `"v2"` (legacy) → existing v2 path (`v2.` prefix, single-shot ECDH)
- everything else → drop with `unsupported_envelope_version`

Web demo does not have a session store yet — for v3 we need IndexedDB-
backed session state per conversation. Layout:

```
idb store: 'crypto-sessions'
key: conversationId
value: {
  v: 3,
  rootKey, sendChainKey, receiveChainKey,
  sendCounter, receiveCounter,
  sendRatchetPriv, sendRatchetPub,        // base64url
  lastSeenPeerPub,
  hasReceivedSinceLastSend,
  skippedKeys: {"<peerPub>|<ctr>": "<keyB64>"}  // bounded to 1000 entries
}
```

Encrypt the whole blob at rest with a per-device AES-GCM key derived
from `crypto.subtle.deriveKey` over a non-extractable master key stored
in IndexedDB (Origin-bound). Browser sandboxing prevents other origins
from reading; user wipe clears.

### Phase W.3 — mobile reads both, writes v3

Mobile already runs the v2 ratchet. Update wire prefix from `v2.` to
`v3.` (i.e. drop the legacy fallback at parse). Drop the legacy v2
single-shot path on mobile because it never spoke that variant — the
`v2` string lived in the DTO for compatibility, the actual mobile wire
was already ratcheted.

### Phase W.4 — server enforces v3-only

After W.2 and W.3 ship and a deprecation window passes (~30 days for
private beta), drop `"v2"` from `SUPPORTED_ENVELOPE_VERSIONS`. Old web
demo clients that don't update can no longer send. They can still
decrypt their own historical v2 messages locally (read-side never
removed in the client).

## Test matrix (must pass before merge)

| # | Scenario | Expected |
|---|---|---|
| 1 | Web↔Web first-message | v3 envelope, mutual decrypt |
| 2 | Web↔Mobile first-message | v3 envelope, mutual decrypt |
| 3 | Mobile↔Mobile (regression) | v3 envelope, mutual decrypt |
| 4 | Stolen X25519 identity replays past v3 envelopes | All decrypts fail (FS) |
| 5 | Stolen mid-session state, then peer replies | New envelopes undecryptable post-rotation (PCS) |
| 6 | Out-of-order delivery, ctr 0,3,1,2 | All four decrypt correctly |
| 7 | Replay ctr=2 after consumption | Rejected |
| 8 | Skipped-key cap exceeded (>1000) | Drop oldest, no crash |
| 9 | App restart, queued receives | Sessions restore, decrypt continues |
| 10 | DoS: peer rotates ratchet 1000× before any message | No CPU or memory blowup |
| 11 | v2 envelope arrives in v3-only mode | Rejected with `unsupported_envelope_version` |
| 12 | v2 envelope arrives in dual mode | Decrypted via legacy path |

## External review questions

The auditor must specifically answer:

1. Does the AD construction prevent envelope re-targeting (replaying an
   envelope addressed to A as if addressed to B)?
2. Is the chain-A/chain-B tie-break by deviceId vulnerable to an attacker
   who can pick their UUID? (Answer expected: no, because the tie-break
   is informational only — both sides compute the same shared secret.)
3. Is the 1000-entry skipped-key cap sufficient? Is the eviction policy
   safe (current: oldest-first)?
4. Is the rootKey/chainKey separation cryptographically sound, or does
   the salt=conversationId binding leak structure?
5. Does the per-message `salt=ctr-bytes` provide enough domain
   separation, or should it be a 12-byte nonce?
6. Is base64url-encoded session state in IndexedDB an acceptable risk on
   web compared to OS-keystore on mobile?

## Open questions for product

- **Group ratchet timing.** v3 covers 1:1 only. Group chats today
  encrypt with the same conversation key for all members; that's a
  Sender-Keys problem, not a v3 problem. Schedule v4 for groups.
- **Cross-device v3 state migration during transfer.** After Phase U the
  old device is revoked atomically. The new device must re-bootstrap
  every conversation from inbound — no v3 state migration. That's
  acceptable: the new device sees existing messages decrypted from the
  cipher cache (server already has ciphertext + the new device's
  identity key works because it shares the same handle's identity).
  Validate this assumption with a write-up before merge.

## Implementation cost estimate

| Phase | Effort | Risk |
|---|---|---|
| W.1 server const | 1h | trivial |
| W.2 web demo v3 | 4-5d | medium — IndexedDB session encryption is new |
| W.3 mobile drop legacy v2 | 2d | low — mobile already ratchets |
| W.4 server v2 drop | 1d | low (after deprecation window) |
| External review | 2-4w wall clock | external dependency |

Total client-engineering: ~7-8 days. Wall-clock with audit: ~6-8 weeks.

## Decision required before W.2 starts

1. Confirm the AD construction.
2. Confirm session-storage choice on web (IndexedDB-encrypted vs
   localStorage-only vs WebCrypto-CryptoKey-only).
3. Confirm we want the deprecation window (W.4) or hard cutover.
