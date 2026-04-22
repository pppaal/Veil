# VEIL Crypto Envelope Specification

This document is the canonical wire-format specification for the VEIL production
crypto adapter (`LibCryptoAdapter`, adapter id `lib-x25519-aes256gcm-v2`). It
exists so external auditors, future re-implementers, and anyone reasoning about
backwards compatibility have a single source of truth that is independent of
any specific language or source file.

The v2 adapter provides a full Double Ratchet (DH ratchet + symmetric hash
ratchet) giving both forward secrecy and post-compromise security. The
envelope wire layout is identical to v1 — the adapter id was bumped because
the interpretation of the first 32 bytes (now a rotating DH ratchet public
key rather than a static ephemeral) and the key-schedule semantics changed.

The reference implementation lives in
[lib_crypto_adapter.dart](../apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart).
When this document and the code disagree, the code is correct and this document
is stale — file a correction.

## Constants

| Name                           | Value                         |
| ------------------------------ | ----------------------------- |
| Envelope version               | `veil-envelope-v1`            |
| Attachment algorithm hint      | `x25519-aes256gcm`            |
| Adapter id                     | `lib-x25519-aes256gcm-v2`     |
| Session schema version         | `2`                           |
| AES-GCM key size               | 256 bits                      |
| AES-GCM nonce size             | 12 bytes                      |
| AES-GCM MAC size               | 16 bytes                      |
| X25519 public key size         | 32 bytes                      |
| Message counter size           | 4 bytes, big-endian unsigned  |
| HKDF hash                      | SHA-256                       |
| HKDF output length             | 32 bytes                      |
| Signing algorithm              | Ed25519                       |
| Base64 variant                 | base64url, no `=` padding     |

## Identity material

`DeviceIdentityProvider.generateDeviceIdentity(deviceId)` produces three fields.

- `identityPublicKey` = base64url(Ed25519 public key, 32 bytes)
- `identityPrivateKeyRef` = base64url(utf8 JSON):
  ```json
  { "ed25519": "<b64url 32 bytes>", "x25519": "<b64url 32 bytes>" }
  ```
- `signedPrekeyBundle` = base64url(utf8 JSON):
  ```json
  {
    "v": 1,
    "x25519": "<b64url 32 bytes, recipient X25519 public>",
    "sig": "<b64url Ed25519 signature over the raw x25519 public bytes>"
  }
  ```

The Ed25519 signature is computed over the 32 raw bytes of the X25519 public
key, not over the JSON.

## Envelope JSON shape

`CryptoEnvelopeCodec.encodeApiEnvelope` produces:

```json
{
  "version": "veil-envelope-v1",
  "conversationId": "<string>",
  "senderDeviceId": "<string>",
  "recipientUserId": "<string>",
  "ciphertext": "<base64url of the binary frame below>",
  "nonce": "<base64url of 12-byte AES-GCM nonce>",
  "messageType": "text|image|file|voice|system|sticker|reaction|call",
  "expiresAt": "<RFC 3339 UTC, optional>",
  "attachment": "<AttachmentReference JSON, optional>"
}
```

`expiresAt` and `attachment` are omitted (not `null`) when absent on the sender.

## Ciphertext binary frame

Decoded from the envelope's `ciphertext` field:

```
+------------------+---------------+-----------------+---------+
| ratchetPub (32)  | counter (4 BE)| aesGcmCt (var)  | mac (16)|
+------------------+---------------+-----------------+---------+
```

- `ratchetPub`: the sender's current DH-ratchet X25519 public key. Rotates
  on a DH ratchet step (see "DH ratchet"). On the first send after a receive,
  the sender generates a fresh ratchet keypair and this field changes. On
  consecutive sends with no intervening receive, this field stays the same.
- `counter`: 4-byte big-endian unsigned integer, the sender's
  `session.sendCounter` at encrypt time. Counter resets to 0 on every DH
  ratchet step.
- `aesGcmCt`: AES-256-GCM ciphertext over the plaintext payload.
- `mac`: 16-byte AES-GCM authentication tag.

Minimum valid frame length is 52 bytes (32 + 4 + 0 + 16). Frames shorter than
this MUST be rejected as invalid.

## Plaintext payload

The AES-GCM plaintext is UTF-8 encoded JSON:

```json
{
  "body": "<string>",
  "kind": "text|image|file|voice|system|sticker|reaction|call",
  "expiresAt": "<RFC 3339 UTC, optional>",
  "att": {
    "id": "<attachmentId>",
    "sk": "<storageKey>",
    "ct": "<contentType>",
    "sz": <sizeBytes>,
    "h": "<sha256>",
    "ek": "<encryptedKey b64url>",
    "n": "<nonce b64url>",
    "ah": "<algorithmHint, optional>"
  }
}
```

Short keys inside `att` are intentional — attachment references ride inside the
encrypted payload on every message, so key length has an observable effect on
envelope size.

## Session bootstrap

### Outbound (initiator)

1. Decode the recipient's `signedPrekeyBundle`; extract the 32-byte X25519
   public key.
2. Generate a fresh X25519 ratchet keypair.
3. Compute `sharedSecret = X25519(ratchetPriv, remoteX25519Pub)`.
4. Compute `fingerprint = base64url(SHA-256(remoteIdentityPublicKeyBytes)[:16])`.
5. Derive the root key and initial chain keys (see below).
6. Remember the recipient's prekey public as `lastSeenPeerRatchetPub`. Set
   `hasReceivedSinceLastSend = false` (the initiator's first send must not
   rotate before deriving keys).
7. Persist the session under key `conversationId`.

### Inbound (responder)

1. Extract `peerRatchetPub` from the first 32 bytes of the incoming frame's
   decoded ciphertext.
2. Load the local X25519 private key from `identityPrivateKeyRef`.
3. Compute `sharedSecret = X25519(localX25519Priv, peerRatchetPub)`.
4. Derive the root key and initial chain keys as below.
5. Set the responder's ratchet keypair placeholder to the local X25519 identity
   keypair, `lastSeenPeerRatchetPub = peerRatchetPub`, and
   `hasReceivedSinceLastSend = true` so the responder's first outbound send
   rotates to a fresh ratchet keypair before encrypting.
6. Persist the session under `conversationId`.

## Root key and chain key derivation

```
rootKey = HKDF-SHA256(
  ikm  = sharedSecret,
  salt = utf8(conversationId),
  info = utf8("veil-root-v2"),
  L    = 32 bytes,
)

chainA = HKDF-SHA256(
  ikm  = sharedSecret,
  salt = utf8(conversationId),
  info = utf8("veil-chain-A-v2"),
  L    = 32 bytes,
)

chainB = HKDF-SHA256(
  ikm  = sharedSecret,
  salt = utf8(conversationId),
  info = utf8("veil-chain-B-v2"),
  L    = 32 bytes,
)
```

The peer with the lexicographically smaller `deviceId` is "A" and uses
`chainA` as its initial send chain and `chainB` as its initial receive chain.
The other peer mirrors. This ordering MUST be computed identically on both
sides. After the first DH ratchet step, chain assignment is driven by the
ratchet rather than by deviceId.

## DH ratchet

On every send where `hasReceivedSinceLastSend == true`, the sender performs a
DH ratchet step before deriving a message key:

```
newRatchetKp     = fresh X25519 keypair
dhOut            = X25519(newRatchetPriv, lastSeenPeerRatchetPub)
kdfOutput        = HKDF-SHA256(
  ikm  = dhOut,
  salt = rootKeyBytes,
  info = utf8("veil-dh-rk-v2"),
  L    = 64 bytes,
)
rootKey          = kdfOutput[0..32]
sendChainKey     = kdfOutput[32..64]
sendCounter      = 0
ratchetPub       = newRatchetPub     // goes on the next envelope wire
hasReceivedSinceLastSend = false
```

Receivers perform the symmetric step whenever an incoming envelope's
`ratchetPub` differs from `lastSeenPeerRatchetPub`: `dhOut =
X25519(localRatchetPriv, incomingRatchetPub)`, same HKDF with the same `info`
string, result splits into `(rootKey, newReceiveChainKey)`, and `receiveCounter`
resets to 0. The old receive chain's skipped-message keys are preserved for
out-of-order stragglers and are keyed by the pre-rotation peer pub so they do
not alias into the new chain.

## Per-message key derivation (symmetric ratchet)

```
messageKey_n = HKDF-SHA256(
  ikm  = sendChainKey,
  salt = utf8("veil-msg-n" + decimal(counter_n)),
  info = utf8("veil-msg-v1"),
  L    = 32 bytes,
)

sendChainKey_{n+1} = HKDF-SHA256(
  ikm  = sendChainKey_n,
  salt = [0x00],
  info = utf8("veil-chain-next-v1"),
  L    = 32 bytes,
)
```

The chain key is advanced after every send, so the previous chain key is
unreachable. Receivers perform the same advance lazily as counters arrive.
A DH ratchet step (above) replaces the current chain entirely and resets the
counter to 0.

### Out-of-order and replay handling

Receivers MAY accept a counter ahead of the current `receiveCounter` by
advancing the receive chain and stashing intermediate message keys for later
use. Skipped keys are indexed by `(peerRatchetPub, counter)` so stragglers
from a pre-rotation DH epoch do not alias counters on the post-rotation chain.
The reference implementation caps the skip window at 1000 counters per chain
to prevent a hostile peer from forcing unbounded HKDF work. Counters strictly
below the consumed window on the same peer pub MUST be rejected as replay.

## Attachment wrapping

A random 32-byte content-encryption key is generated per attachment. It is
encrypted to the recipient via:

```
ephKeyPair       = fresh X25519 keypair
wrapSharedSecret = X25519(ephPriv, recipientX25519Pub)
wrapKey          = HKDF-SHA256(
  ikm  = wrapSharedSecret,
  salt = nonce,               // the same 12-byte AES-GCM nonce
  info = utf8("veil-attachment-wrap-v1"),
  L    = 32 bytes,
)
wrappedKey       = AES-256-GCM(plaintext = contentKey, key = wrapKey, nonce = nonce)
```

The encrypted key on the wire is:

```
+-----------------+------------------+---------+
| ephPub (32)     | wrappedKeyCt     | mac (16)|
+-----------------+------------------+---------+
```

base64url-encoded into `AttachmentReference.encryptedKey`. The AES-GCM nonce is
published in `AttachmentReference.nonce` and `AttachmentReference.algorithmHint`
is set to `x25519-aes256gcm`.

## Version policy

- The `version` string on an envelope MUST NOT be reused for a materially
  different wire format. Breaking changes require a new version string and a
  migration path that lets peers running the previous version fail cleanly.
- Any change to: HKDF `info` strings, counter encoding, frame layout, chain-key
  ordering, or key sizes is a breaking change.
- Any addition of optional JSON fields that older peers can ignore without loss
  of correctness is a compatible change.

## Audit surface

The following invariants are intended to be verifiable by an external reviewer
without running the code:

- Server never has access to any symmetric session key, chain key, message key,
  X25519 private key, or Ed25519 private key. All private material remains on
  device.
- Plaintext body and attachment metadata are encrypted inside the GCM payload;
  the envelope JSON exposes only the counterparty-visible routing fields and
  the opaque ciphertext blob.
- Forward secrecy: compromise of the current chain key does not reveal
  previously derived message keys, because each advance discards the prior
  chain key.
- Post-compromise security: a DH ratchet step mixes a fresh ECDH output into
  the root key, so an adversary who captures the full session state loses
  visibility as soon as either side performs a DH step (on the next turn flip).
- Replay protection: receivers reject counters below their consumed window on
  the same peer ratchet pub.
