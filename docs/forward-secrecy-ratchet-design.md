# Double Ratchet — v2 Design

## Goal

Give VEIL's message encryption both **forward secrecy** (compromise of current
state reveals no past messages) and **post-compromise security** (compromise
heals automatically after a reply turn). v1 delivered only the first. v2 adds
a DH ratchet on top of the symmetric hash ratchet and persists session state
so the chain survives app restart.

## v2 scope (shipped)

Location: `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart`.

### Session state

Each conversation holds a `_SessionState` with:

- `rootKey` — seeds every DH step, rotates on each step.
- `sendChainKey`, `receiveChainKey` — symmetric chains advanced per message.
- `sendCounter`, `receiveCounter` — reset on DH rotation.
- `currentSendRatchetPriv` / `currentSendRatchetPub` — our active ratchet
  keypair; the pub goes on the wire.
- `lastSeenPeerRatchetPub` — the peer's ratchet pub from the most recent
  inbound envelope; a mismatch triggers a receive DH step.
- `hasReceivedSinceLastSend` — latched true on every successful receive,
  cleared after a send-side DH rotation. "Is it our turn" signal.
- `skippedMessageKeys` — keyed by `"<peerPubB64>|<counter>"` so stragglers
  from a pre-rotation epoch don't alias post-rotation counters.

### Chain derivation

Initial ECDH remains unchanged. From the shared secret we derive:

```
rootKey  = HKDF(sharedSecret, nonce=conversationId, info="veil-root-v2")
chainA   = HKDF(sharedSecret, nonce=conversationId, info="veil-chain-A-v2")
chainB   = HKDF(sharedSecret, nonce=conversationId, info="veil-chain-B-v2")
```

The peer with the lexicographically smaller `deviceId` adopts `chainA` as its
send chain; the other mirrors.

### Per-message key derivation and advance

```
messageKey(n)   = HKDF(chainKey_n, nonce=f"veil-msg-n{n}", info="veil-msg-v1")
chainKey_{n+1}  = HKDF(chainKey_n, nonce=[0], info="veil-chain-next-v1")
```

### DH ratchet step

**Send side** (runs at the start of `encryptMessage` iff
`hasReceivedSinceLastSend == true`):

1. Generate a fresh X25519 keypair.
2. `dh = X25519(newPriv, lastSeenPeerRatchetPub)`.
3. `(newRootKey, newSendChain) = HKDF(dh, salt=rootKey, info="veil-dh-rk-v2",
   outputLength=64).split(32, 32)`.
4. Replace `rootKey`, `sendChainKey`. Reset `sendCounter=0`. Swap ratchet
   keypair. Clear `hasReceivedSinceLastSend`.

**Receive side** (runs in `decryptMessage` iff the wire's first 32 bytes
differ from `lastSeenPeerRatchetPub`):

1. `dh = X25519(currentSendRatchetPriv, incomingPeerPub)`.
2. `(newRootKey, newReceiveChain) = HKDF(dh, salt=rootKey, ...)`.
3. Replace `rootKey`, `receiveChainKey`. Reset `receiveCounter=0`. Update
   `lastSeenPeerRatchetPub = incomingPeerPub`.

Both sides compute the same `dh` by X25519 symmetry
(`X25519(a,B)==X25519(b,A)` when `A=aG, B=bG`), so the root/chain split
agrees.

### Wire format

Unchanged from v1:

```
ciphertext = [senderRatchetPub:32] [counter:u32 BE] [AEAD ciphertext] [AEAD mac:16]
```

The semantics of `senderRatchetPub` now carry the *rotating* DH pub. The
counter is the offset into the *current* send chain (resets on rotation).

### Receive-side bootstrap

First inbound for an unbootstrapped conversation:

1. App-layer pulls the 32-byte sender ephemeral pub via
   `InboundEnvelopeInspector.extractSenderEphemeralPublicKey`.
2. Controller calls
   `ConversationSessionBootstrapper.bootstrapSessionFromInbound` with that
   pub plus the receiver's stored X25519 identity private key.
3. Receiver runs `ECDH(localX25519Priv, senderEphemeralPub)` → same
   `sharedSecret` the sender already derived → identical root + chains.
4. `lastSeenPeerRatchetPub` is set to the sender's ephemeral from the wire;
   `hasReceivedSinceLastSend=true` so the receiver's first reply will rotate.

No handshake round-trip required. The controller plumbs this via an
`identityPrivateRefLoader` callback so secure storage stays isolated from
the crypto layer.

### Session persistence

`LibCryptoAdapter.setSessionPersistence(persister: ...)` wires a callback
invoked after every mutating operation (bootstrap, encrypt, decrypt). Each
session serializes as a JSON snapshot:

```json
{
  "v": 2,
  "rootKey": "b64", "sendChainKey": "b64", "receiveChainKey": "b64",
  "sendCounter": 3, "receiveCounter": 5,
  "sendRatchetPriv": "b64-32", "sendRatchetPub": "b64-32",
  "lastSeenPeerPub": "b64-32",
  "hasReceivedSinceLastSend": true,
  "remoteIdentityFingerprint": "...", "localDeviceId": "...",
  "remoteDeviceId": "...",
  "skippedKeys": {"<peerPub>|<ctr>": "<keyB64>", ...}
}
```

Snapshots are stored by `SecureStorageService` as a single blob under
`veil.crypto.session_snapshots` (JSON map keyed by conversationId). Single-
blob layout avoids depending on `FlutterSecureStorage.readAll`, which is not
uniformly supported across platforms.

On controller startup (first authenticated `applySession` call),
`sessionSnapshotRestorer` pulls all snapshots and hands them to
`LibCryptoAdapter.restoreSessionsFromSnapshots`, which calls
`_SessionState.tryRestore` per snapshot. Snapshots from an incompatible
schema version are silently dropped (lazy re-bootstrap on next inbound).

Secret material lives inside platform-encrypted secure storage (Keychain /
EncryptedSharedPreferences). `wipeLocalDeviceState` clears snapshots along
with other device secrets on logout.

### Tests

- `apps/mobile/test/forward_secrecy_test.dart` — ciphertext distinctness,
  bulk ratchet stability, fail-fast on missing session.
- `apps/mobile/test/crypto_round_trip_test.dart` — Alice→Bob decrypt via
  inbound-bootstrap, multi-message ratchet, out-of-order delivery, replay
  rejection, corrupt identity bundle refused.
- `apps/mobile/test/dh_ratchet_test.dart` — DH rotation only on turn-flip
  (not per message), ratchet pub unique across 12 ping-pong turns, snapshot
  round-trip preserves send-chain position, restart + queued receive still
  triggers DH rotation on next send.

## Security properties summary

| Property | v1 | v2 | Notes |
|---|---|---|---|
| Forward secrecy (per-message) | ✅ | ✅ | HKDF-one-way chain advance |
| Post-compromise security | ❌ | ✅ | DH step mixes fresh ECDH into root |
| Out-of-order delivery | ✅ | ✅ | Up to 1000 skipped keys, keyed by (peerPub, counter) |
| Replay protection | ✅ | ✅ | Consumed counters rejected |
| DoS ceiling on skipped-key derivation | ✅ | ✅ | `_maxSkippedKeys = 1000` |
| Survives app restart | ❌ | ✅ | Encrypted snapshot in secure storage |

## Deferred to v3

Not launch blockers.

1. **Cross-epoch out-of-order tolerance.** Stragglers from a chain that's
   been superseded by a DH step are currently dropped (message key was
   never stashed). Standard DR keeps a `previousChainLen` + stashes trailing
   keys of the old chain during the step. Add this if user reports show
   meaningful loss on turn-flips under high concurrency.
2. **Skipped-key expiry.** Stashed keys live for the life of the session.
   Add TTL (N minutes / M new messages) to bound worst-case memory.
3. **Manual session rekey.** User-initiated "rekey this conversation" that
   wipes chain state and re-runs ECDH with a fresh ephemeral. Hook up to
   the Security Status screen post-suspected-compromise.
4. **Snapshot write batching / debouncing.** Every message triggers a
   secure-storage write; fine for chat-interactive rates but wasteful under
   bulk sync. Debounce with a ~500ms tail, flush on app-pause.
5. **Schema migration.** v2 is the first on-disk schema. When v3 ships,
   `_SessionState.tryRestore` must either migrate or drop + re-bootstrap on
   next inbound.
