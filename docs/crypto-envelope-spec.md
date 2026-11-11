# VEIL Crypto Envelope Specification

This document is the canonical wire-format specification for the VEIL production
crypto adapter (`LibCryptoAdapter`, adapter id `lib-x3dh-x25519-aes256gcm-v4`). It
exists so external auditors, future re-implementers (the web client ports it
next), and anyone reasoning about backwards compatibility have a single source of
truth that is independent of any specific language or source file.

The adapter speaks two protocols:

- **Protocol v2** (`veil-envelope-v2`, the default and the only one new sessions
  use with v2 bundles): X3DH with signed and one-time prekeys authenticates
  **both** parties, then a Double Ratchet with the previous-chain length (PN) in
  every header, AEAD-bound routing fields and attachments carried inside the
  ratchet. Normative section below.
- **Legacy protocol v1** (`veil-envelope-v1`): spoken only with peers that still
  publish v1 bundles. Its handshake authenticates only the responder, so
  everything decrypted on it is reported as `legacyUnauthenticated`. Kept
  byte-compatible; documented after the v2 section.

The reference implementation lives under
[apps/mobile/lib/src/core/crypto/](../apps/mobile/lib/src/core/crypto/)
(`x3dh/`, `ratchet/`, `payload/`, `attachment/`, adapted by
[lib_crypto_adapter.dart](../apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart)).
An independent node:crypto implementation of protocol v2 lives in
[scripts/crypto-test-vectors.mjs](../scripts/crypto-test-vectors.mjs); every byte
both produce is pinned in `packages/shared/test-vectors/crypto-kat.json`
(`vectors.protocolV2`). When this document and the code disagree, the code is
correct and this document is stale — file a correction.

---

## Protocol v2 (`veil-envelope-v2`) — normative

### Notation

- `||` is byte concatenation; `utf8(s)` the UTF-8 bytes of `s`.
- `u16be`, `u32be`, `u64be`: unsigned big-endian integers of 2, 4, 8 bytes.
- `lp(s) = u16be(len(utf8(s))) || utf8(s)`.
- `b64u` is base64url without `=` padding.
- `HKDF(ikm, salt, info, L)` is HKDF-SHA256 (RFC 5869). `DH(priv, pub)` is
  X25519 (RFC 7748); an all-zero DH output MUST be rejected.
- `IKed` is a device's Ed25519 identity public key, `IKx` its X25519 identity
  key, `SPK` its signed prekey, `OPK` a one-time prekey, `EK` the initiator's
  handshake ephemeral.

### Constants

| Name                                  | Value                                   |
| ------------------------------------- | --------------------------------------- |
| Envelope version                      | `veil-envelope-v2`                      |
| Adapter id                            | `lib-x3dh-x25519-aes256gcm-v4`          |
| Attachment algorithm                  | `aes256gcm-v2`                          |
| Session snapshot schema               | `4`                                     |
| IKx certification label               | `veil-ikx-v2`                           |
| SPK signature label                   | `veil-spk-v2`                           |
| X3DH info label                       | `veil-x3dh-v2`                          |
| Frame AAD label                       | `veil-frame-aad-v4`                     |
| Attachment AAD label                  | `veil-att-v2`                           |
| Root / message / chain KDF labels     | `veil-dh-rk-v2` / `veil-msg-v1` / `veil-chain-next-v1` (unchanged from v1) |
| "No one-time prekey" id               | `0xFFFFFFFF`                            |
| Max keys stashed by one frame         | 200 (PN stash and N stash together)     |
| Max skipped keys per session          | 1000, oldest evicted first              |
| Skipped-key lifetime                  | 7 days                                  |
| Max SPK age / future skew at initiate | 60 days / 1 day                         |
| Superseded SPK grace                  | 14 days after its successor was created |
| Archived states per conversation      | 5, each kept 30 days after its last use |

### Identity keys and the bundle (contract C1)

A device publishes `identityPublicKey = b64u(IKed)` and

```
ikxSig = Ed25519(IK, utf8("veil-ikx-v2") || IKx)
spkSig = Ed25519(IK, utf8("veil-spk-v2") || u32be(spkId) || u64be(spkTs) || SPK)
signedPrekeyBundle = b64u(utf8(compact JSON))
```

The JSON has exactly these keys, in this order, no whitespace:
`{"v":2,"ikx":b64u(IKx),"ikxSig":b64u(ikxSig),"spkId":<u32>,"spk":b64u(SPK),"spkTs":<ms since epoch>,"spkSig":b64u(spkSig)}`.

Vector (IK seed `0x11`×32, IKx private `0x55`×32, SPK private `0x66`×32,
spkId 1, spkTs 1767225600000): `identityPublicKey =
0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc` and the bundle string is
`vectors.protocolV2.bundle.signedPrekeyBundle`.

An initiator MUST verify both signatures against `identityPublicKey` and MUST
reject `spkTs` older than 60 days or more than 1 day in the future. Any failure
aborts session setup; there is no fallback. A bundle whose `v` is not 2 is a
legacy v1 bundle and selects the legacy protocol.

One-time prekeys are X25519 keys published with a `u32` keyId. Ids are
allocated monotonically and never reused; `0xFFFFFFFF` is reserved. OPKs are
not signed: a substituted OPK can only remove DH4's extra forward secrecy.

The device-local identity private ref (never transmitted) is
`b64u(JSON {"v":2,"ed25519":b64u(seed),"x25519":b64u(IKx priv),"spk":{"id","priv","ts"}})`.
A fresh identity uses spkId 1. Rotating draws a new SPK with id `max + 1`; a
v1 ref (no `spk`) is upgraded by promoting its X25519 key to IKx.

### X3DH

The initiator A, holding B's verified bundle and optionally a claimed OPK:

```
EK  = fresh X25519 key pair
DH1 = DH(IKx_A, SPK_B)        // authenticates A: needs A's IKx private key
DH2 = DH(EK, IKx_B)
DH3 = DH(EK, SPK_B)
DH4 = DH(EK, OPK_B)           // only when an OPK was claimed
SK  = HKDF(0xFF*32 || DH1 || DH2 || DH3 [|| DH4], salt = 0x00*32,
           info = utf8("veil-x3dh-v2") || IKed_A || IKed_B, L = 32)
AD  = IKed_A || IKx_A || IKed_B || IKx_B
preKeyHeader (168 bytes) = IKed_A(32) || IKx_A(32) || ikxSig_A(64) || EK(32)
                           || u32be(spkId) || u32be(opkId or 0xFFFFFFFF)
```

The responder B processes a PreKey frame whose `EK` matches no stored state:

1. Load the SPK named by `spkId`: the current one, or a superseded one whose
   successor is at most 14 days old. Otherwise fail (`spk_unavailable`).
2. If `opkId != 0xFFFFFFFF`, load that OPK. If it is gone, fail
   (`opk_unavailable`) without changing any state.
3. Verify `ikxSig_A` against `IKed_A`; otherwise fail (`bad_ikx_signature`).
4. Mirror DH1..DH4 with its private keys and derive `SK` and `AD`.
5. Initialise its ratchet (below) and receive the frame. The AEAD MUST verify.
6. Only then decide whether the identity is acceptable (see "Session records
   and glare"), so the decision is only ever made about a proven identity. A
   refusal yields `identityRejected`, stores nothing and consumes no OPK.
7. Install the state (see "Session records and glare"), persist it, and only
   then delete the OPK private key. A failed delete does not undo the
   session; the OPK is still treated as spent until the app restarts.

A forged initiator holding only public bundles cannot compute DH1 and its frame
fails authentication. Both sides record `remoteIdentityFingerprint =
hex(SHA-256(IKed_remote))`, never empty.

A PreKey frame without an OPK can be replayed. While its state is stored, the
replay lands on that state and is `replayed`; once the state has aged out of
the record (below), the same frame would install it again. This is inherent to
X3DH, so initiators SHOULD claim an OPK whenever the directory has one.

### Double Ratchet

```
KDF_RK(rk, dh) = HKDF(ikm = dh, salt = rk, info = "veil-dh-rk-v2", L = 64)
                 -> (rk' = out[0..32], ck = out[32..64])
messageKey(ck, N) = HKDF(ikm = ck, salt = utf8("veil-msg-n" + decimal(N)),
                         info = "veil-msg-v1", L = 32)
nextChain(ck)     = HKDF(ikm = ck, salt = 0x00, info = "veil-chain-next-v1", L = 32)
```

Initialisation:

- A: `DHs` = fresh key pair (drawn after `EK`); `(RK, CKs) = KDF_RK(SK, DH(DHs, SPK_B))`;
  `DHr = SPK_B`; `Ns = PN = Nr = 0`; no receiving chain; A repeats
  `preKeyHeader` in every frame until a frame from B decrypts on this state.
- B: `DHs` = the SPK key pair; `RK = SK`; no chains.

Sending: if a receive DH step happened since the last send, first do
`PN = Ns; Ns = 0; DHs = fresh; (RK, CKs) = KDF_RK(RK, DH(DHs, DHr))`. Then
`mk = messageKey(CKs, Ns); CKs = nextChain(CKs); Ns += 1`. Only a receive DH
step arms the next send step (Signal's DHRatchet, with the send half deferred
to the next send; the derived keys are identical).

Receiving header `(pub, PN, N)` always runs on a copy of the state, committed
only after the AEAD verifies:

1. If a skipped key for `(pub, N)` exists, use it and change nothing else.
2. If `pub` is a ratchet key the peer has moved past, the frame is `replayed`.
3. If `pub != DHr`: when a receiving chain exists, stash `messageKey` for
   `Nr..PN-1` under the **old** `DHr`; then `(RK, CKr) = KDF_RK(RK, DH(DHs, pub))`,
   `Nr = 0`, `DHr = pub`, and arm the next send step. Otherwise, if `N < Nr`,
   the frame is `replayed`.
4. Stash `messageKey` for `Nr..N-1` under `pub`, derive the key for `N`,
   `Nr = N + 1`.

One frame may stash at most 200 keys in total; a session keeps at most 1000
(oldest evicted) for at most 7 days. Superseded root, chain and ratchet-private
buffers are overwritten after every commit.

A Normal frame is tried on up to six states (current plus archived), and each
attempt may do one DH step and derive up to 200 keys before the AEAD rejects
it. A forged frame therefore costs the receiver a bounded few thousand HKDF
calls; this is the protocol's CPU amplification ceiling.

A manual rekey (forcing a send step without a receive) is refused while the
state still awaits the peer's first reply: until then the peer can only reach
later chains through the ratchet key in the handshake frames, so a second step
would strand every later frame if those were lost. Known limitation: a forced
step is only sound when the peer has not sent since our last send. If a reply
is still in flight, the forced step builds on a root key the peer has already
ratcheted past and the session desynchronises until it is re-bootstrapped.
The manual rekey must be redesigned or removed before it is exposed further.

### Frame

```
frame = 0x02 || type || [preKeyHeader] || ratchetPub(32) || u32be(PN) || u32be(N)
        || ciphertext || tag(16)
type  = 0x01 PreKey (carries preKeyHeader) | 0x02 Normal
```

`header` is every byte before `ciphertext`. Minimum lengths: 58 (Normal) and
226 (PreKey) bytes. The envelope carries `version = "veil-envelope-v2"`,
`ciphertext = b64u(frame)` and `nonce = b64u(12 random bytes)` (the AES-GCM
nonce; message keys are single-use).

### AEAD associated data (v4)

```
aad = utf8("veil-frame-aad-v4") || lp(version) || lp(conversationId)
      || lp(senderDeviceId) || lp(messageType) || header || AD
```

All values are the envelope's transmitted fields. Re-labelling a frame (another
conversation, sender, kind or version) breaks the tag. `expiresAt` is
deliberately **not** bound (contract C4): the server may clamp the outer value,
the authenticated expiry travels in the payload, and receivers expire at
`min(inner, outer)`. A receiver treats any envelope whose version is not
`veil-envelope-v1` as v2, so relabelled versions fail authentication.

### Inner payload

```
{"pv":2,"b":<body>,"k":<messageType>,"x":<expiresAt ms or null>,
 "att":null | {"id","ck","n","d","ct","sz","alg"}}
```

Compact JSON, all five keys always present, in this order. It is ISO/IEC 7816-4
padded (append `0x80`, then `0x00`) to the smallest bucket of 256, 512, ...,
65536, then multiples of 65536, that fits `len + 1`. Receivers also accept the
legacy shapes `{"body","kind","expiresAt"(RFC 3339),"att"}` with short
(`id, sk, ct, sz, h, ek, n, ah`) or long (`attachmentId, storageKey, ...`)
attachment keys. The decrypted kind, not the outer `messageType`, decides how a
message renders (contract C5).

### Attachments

```
key, nonce = 32 and 12 random bytes per blob
padded     = ISO7816 pad to padmeLength(len + 1)        // Padmé, PETS 2019
blob       = AES-256-GCM(key, nonce, padded, aad = utf8("veil-att-v2") || utf8(attachmentId))
             as ciphertext || tag
att        = {"id": attachmentId, "ck": b64u(key), "n": b64u(nonce),
              "d": b64u(SHA-256(blob)), "ct": contentType, "sz": plaintext length,
              "alg": "aes256gcm-v2"}
```

`padmeLength(L)` for `L >= 2`: `E = floor(log2 L)`, `S = floor(log2 E) + 1`,
`mask = 2^(E-S) - 1`, result `(L + mask) & ~mask` (and `L` itself for `L < 2`).
The pointer travels **only** inside the payload, so it inherits the ratchet's
forward secrecy and needs no per-recipient wrapping. The outer envelope carries
just `{"attachmentId"}` for blob lifecycle (contract C3); extra outer fields are
accepted and discarded, and receivers never fall back to the outer pointer.
Receivers compare the digest in constant time before decrypting, then unpad.

Interop limitation: on a legacy (v1) session the same raw-key pointer travels
inside the v1 payload. Confidentiality is unchanged (it is still inside the
ratchet), but apps older than v2 cannot open such attachments.

### Session records and glare

A conversation holds a record: the current (sending) state plus up to 5
archived states, most recently used first. Archiving a state or committing a
message on it counts as use, and an archived state is dropped 30 days after its
last use, so a state the peer still sends on is never pruned. A local
bootstrap archives the current state, never destroys it. Every operation on a
conversation is serialized.

Two terms decide which state sends:

- A state's handshake is **pending** while it is our initiation and no frame
  from the peer has decrypted on it yet, or it is the peer's initiation and we
  have not sent on it yet.
- A state's **initiator key** is the `IKed` of the party whose handshake
  created it.

Installing. A PreKey frame whose `EK` matches a stored state is received on
that state. One with a new `EK` creates a state that becomes current, except in
glare: when the current state is our own pending initiation and our `IKed` is
bytewise lexicographically lower than the new state's initiator key, the
current state stays and the new one is archived.

Receiving. A Normal frame is tried on the current state, then on the archived
ones, each on a copy; the first that authenticates is committed. When the state
that receives a frame (a Normal frame, or a PreKey frame whose `EK` it owns) is
archived, it also becomes current, because the peer sends on the state it last
chose (libsignal's `promoteState`). There are two exceptions:

1. Either state is a legacy state, or the two are bound to different remote
   `IKed`. A legacy state would downgrade the conversation, and a state bound to
   an identity the conversation has moved away from must not regain the
   sending role.
2. The current state's handshake is pending and the archived state's initiator
   key is not lower than the current one's (the same initiator included). The
   frame was then sent before the peer saw the pending handshake, or the peer
   is holding on to a handshake that wins the same comparison.

Both peers rank any two handshakes the same way, so the outcome does not depend
on arrival order. Once messages alternate (each side sends only after it has
received), both sides send on one state within two round trips, stop repeating
`preKeyHeader`, and step the DH ratchet on every turn. Crossing messages may
swap both sides at once, but every frame still decrypts and each state keeps
stepping its own ratchet.

Identity binding: when an identity verifier is configured (the trust store), it
decides whether an authenticated PreKey frame may install its state, including
an identity change in an established conversation, so it MUST pin identities
itself. Without one, the conversation is bound to the remote `IKed` of its most
recent v2 state (the current state if it is v2, otherwise the most recently
used archived v2 state): a PreKey frame from any other identity yields
`identityRejected`, stores nothing and consumes no OPK. Without this rule, any
genuine identity a hostile server routes into an established conversation
would become the sending state and read the replies. Only a local bootstrap
changes the binding. Re-initiation by the same identity and glare are
unaffected, and legacy states never authenticated their peer, so a record
without v2 states binds nothing and a v2 handshake can upgrade it.

### Decrypt results

| Status                  | Meaning                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `ok`                    | authenticated v2 message                                   |
| `failed`                | malformed, unauthenticated, or prekeys unavailable; `failureReason` says which |
| `replayed`              | `(pub, N)` already consumed or its chain left behind       |
| `sessionMissing`        | Normal frame with no matching session                      |
| `awaitingKey`           | group frame whose sender key has not arrived               |
| `identityRejected`      | an authenticated handshake from an identity the conversation is not bound to, or that the verifier vetoed |
| `legacyUnauthenticated` | decrypted from a legacy v1 frame                           |

Non-`ok` results carry a placeholder body (`[Decryption failed]`, ...) that
callers must not render as peer text; they branch on the status.

### Local persistence (informative)

Snapshot schema 4 is `{"v":4,"rev":<int>,"current":<state>,"archived":[{"lastUsedAt","state"}]}`.
`rev` only grows (at least previous + 1 and above any rev read back from
storage for that conversation, even from a snapshot that no longer parses;
seeded from the clock in microseconds), every commit is persisted before the
operation returns (an encrypt never hands out ciphertext whose state could be
lost), and storage refuses, with an error, a write whose `rev` is lower than
the stored one, so the operation fails instead of publishing state that is not
on disk. v2/v3 snapshots restore as the current state of a record. See
[crypto-session-state-migration.md](crypto-session-state-migration.md).

---

## Legacy protocol v1 (`veil-envelope-v1`)

The sections below describe the pre-v2 wire format, still spoken with peers
that publish v1 bundles. It authenticates only the responder.

### Constants (v1)

| Name                           | Value                         |
| ------------------------------ | ----------------------------- |
| Envelope version               | `veil-envelope-v1`            |
| Attachment algorithm hint      | `x25519-aes256gcm` (read-only) |
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

Pre-v2 installs generated these shapes (v2 identities are described above).

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

`CryptoEnvelopeCodec.encodeApiEnvelope` produces (for both protocols):

```json
{
  "version": "veil-envelope-v2",
  "conversationId": "<string>",
  "senderDeviceId": "<string>",
  "recipientUserId": "<string>",
  "ciphertext": "<base64url of the binary frame>",
  "nonce": "<base64url of 12-byte AES-GCM nonce>",
  "messageType": "text|image|file|voice|system|sticker|reaction|call",
  "expiresAt": "<RFC 3339 UTC, optional>",
  "attachment": { "attachmentId": "<id>" }
}
```

`expiresAt` and `attachment` are omitted (not `null`) when absent on the sender.
An envelope received without `version` predates the server persisting it and is
read as `veil-envelope-v1`.

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
this MUST be rejected as invalid. The frame carries no previous-chain length,
so messages from a chain the receiver has already stepped past cannot be
recovered; this is one of the defects protocol v2 fixes.

## AEAD associated data (header binding)

The per-message AES-256-GCM call binds the unencrypted frame header / routing
fields as **associated data (AAD)** so they are authenticated by the GCM tag.

The AAD is the byte concatenation (no separators, fixed field order):

```
aad =   utf8("veil-frame-aad-v3")     // 17-byte domain-separation label
      || ratchetPub                   // 32 bytes, the frame's ratchetPub field
      || counter                      // 4 bytes, big-endian uint32 (frame counter)
      || utf8(senderDeviceId)         // the envelope's senderDeviceId, variable length
```

- `ratchetPub` and `counter` are exactly the first 36 bytes of the binary
  frame above; `senderDeviceId` is the envelope JSON's transmitted sender
  field. All three are values a receiver already has in hand before decrypt.
- `senderDeviceId` is variable-length and placed **last** so it cannot be
  confused with the fixed-size fields ahead of it; no length prefix is needed.
- A mismatch in any bound field makes GCM tag verification fail, so the message
  does not decrypt and the receiver's state is left untouched.

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

### Length padding

Before AES-GCM, the UTF-8 JSON plaintext is length-padded to a coarse bucket
so the ciphertext size reveals only the bucket, not the exact message length.
Padding is ISO/IEC 7816-4: append `0x80`, then `0x00` filler, up to the
smallest bucket that fits `len + 1`. Buckets are powers of two from **256**
bytes up to 64 KiB, then multiples of 64 KiB. Receivers strip trailing `0x00`
then one `0x80`; input without a valid delimiter is treated as un-padded
(legacy-tolerant). Reference: `message_padding.dart`. Protocol v2 uses the same
padding.

## Session bootstrap

### Outbound (initiator)

1. Decode and verify the recipient's v1 `signedPrekeyBundle`; extract the
   32-byte X25519 public key.
2. Generate a fresh X25519 ratchet keypair.
3. Compute `sharedSecret = X25519(ratchetPriv, remoteX25519Pub)`.
4. Compute `fingerprint = base64url(SHA-256(remoteIdentityPublicKeyBytes)[:16])`.
5. Derive the root key and initial chain keys (see below).
6. Remember the recipient's prekey public as `lastSeenPeerRatchetPub`. The
   initiator's first send does not rotate before deriving keys.
7. Persist the session under key `conversationId`.

### Inbound (responder)

1. Extract `peerRatchetPub` from the first 32 bytes of the incoming frame's
   decoded ciphertext (`InboundEnvelopeInspector`; it returns null for v2
   frames, which establish their own session).
2. Load the local X25519 private key from `identityPrivateKeyRef`.
3. Compute `sharedSecret = X25519(localX25519Priv, peerRatchetPub)`.
4. Derive the root key and initial chain keys as below.
5. Set the responder's ratchet keypair placeholder to the local X25519 identity
   keypair and `lastSeenPeerRatchetPub = peerRatchetPub`, and arm a send step so
   the responder's first outbound send rotates to a fresh ratchet keypair.
6. Persist the session under `conversationId`. Nothing here authenticates the
   initiator, hence `legacyUnauthenticated`.

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
The other peer mirrors. After the first DH ratchet step, chain assignment is
driven by the ratchet rather than by deviceId.

## DH ratchet

The root KDF, message-key and chain-key derivations are exactly protocol v2's
`KDF_RK`, `messageKey` and `nextChain`. Legacy sessions run the v2 receive
algorithm without the PN stash (step 3's stash is skipped because the header
has no PN); skipped keys are still looked up before any DH step, so a stashed
straggler can no longer corrupt the session.

## Retired attachment wrapping (read-only)

Before attachment pointers, a random 32-byte content key encrypted the blob
(AES-256-GCM, no AAD) and was wrapped to the recipient's static X25519 identity
key. Nothing produces this format any more; references with
`algorithmHint = "x25519-aes256gcm"` are still decrypted:

```
encryptedKey = ephPub(32) || wrappedKeyCt || mac(16)          // b64url
nonce        = b64u(contentNonce) "." b64u(wrapNonce)
wrapKey      = HKDF-SHA256(ikm = X25519(localX25519Priv, ephPub),
                           salt = ephPub, info = "veil-attachment-wrap-v1", L = 32)
contentKey   = AES-256-GCM-Open(wrapKey, wrapNonce, wrappedKeyCt || mac)
plaintext    = AES-256-GCM-Open(contentKey, contentNonce, blob)
```

## Version policy

- The `version` string on an envelope MUST NOT be reused for a materially
  different wire format. Breaking changes require a new version string and a
  migration path that lets peers running the previous version fail cleanly.
- Any change to: HKDF `info` strings or salts, counter encoding, frame layout,
  bundle JSON key order, chain-key ordering, key sizes, the inner payload shape,
  or the AEAD associated-data construction (labels or the set/order/encoding of
  bound fields) is a breaking change and must update the vectors.
- Any addition of optional JSON fields that older peers can ignore without loss
  of correctness is a compatible change.

## Audit surface

The following invariants are intended to be verifiable by an external reviewer
without running the code:

- Server never has access to any symmetric session key, chain key, message key,
  X25519 private key, or Ed25519 private key. All private material remains on
  device.
- Plaintext body and attachment metadata (key, digest, size, type) are encrypted
  inside the GCM payload; the envelope JSON exposes only routing fields, an
  opaque attachment id and the opaque ciphertext blob.
- Mutual authentication (v2): a session can only be opened by a party holding
  the claimed identity's IKx private key (DH1), and the responder's SPK/IKx are
  certified by its Ed25519 identity key.
- Forward secrecy: compromise of the current chain key does not reveal
  previously derived message keys, because each advance discards the prior
  chain key; attachments inherit it by riding inside the ratchet.
- Post-compromise security: a DH ratchet step mixes a fresh ECDH output into
  the root key, so an adversary who captures the full session state loses
  visibility as soon as either side performs a DH step (on the next turn flip).
- Replay protection: a consumed `(ratchetPub, counter)` never decrypts twice.

---

## Post-quantum hybrid (PROPOSED, not yet implemented)

This section is the wire-format delta for the hybrid X25519 + ML-KEM-768
adapter described in [`post-quantum-migration-spec.md`](post-quantum-migration-spec.md).
It is a **design proposal pending external-audit review**, written against the
legacy v1 layout; it must be rebased onto protocol v2 before implementation
(the KEM leg would join X3DH as a fifth input). Its envelope version string is
`veil-envelope-v3`, because `veil-envelope-v2` now names protocol v2. Only
session establishment carries new material.

### Constant deltas

| Name                      | v1 (as written against)     | Proposal                              |
| ------------------------- | --------------------------- | ------------------------------------- |
| Envelope version          | `veil-envelope-v1`          | `veil-envelope-v3`                    |
| Adapter id                | `lib-x25519-aes256gcm-v3`   | `lib-mlkem768-x25519-aes256gcm-v3`    |
| Session schema version    | `2`                         | `3`                                   |
| Attachment algorithm hint | `x25519-aes256gcm`          | `mlkem768-x25519-aes256gcm`           |
| ML-KEM parameter set      | —                           | ML-KEM-768 (FIPS 203)                 |
| ML-KEM public key size    | —                           | 1184 bytes                            |
| ML-KEM ciphertext size    | —                           | 1088 bytes                            |

AES-256-GCM, X25519, Ed25519, HKDF-SHA256, counter/nonce/mac sizes are all
**unchanged** — the proposal only adds a KEM leg to key agreement.

### Prekey bundle delta

The `signedPrekeyBundle` gains an `mlkem768` field. The Ed25519 signature
now covers the concatenation `x25519_pub_bytes || mlkem768_pub_bytes`
(32 + 1184 bytes), so neither prekey can be stripped or swapped
independently (binds the classical and PQ prekeys to one identity):

```json
{
  "x25519": "<b64url 32 bytes, recipient X25519 public>",
  "mlkem768": "<b64url 1184 bytes, recipient ML-KEM-768 public>",
  "sig": "<b64url Ed25519 signature over (x25519 || mlkem768) raw bytes>"
}
```

A PQ prekey replenishment publishes ML-KEM prekeys alongside X25519 ones.
Prekey storage and bundle bandwidth grow by ~1.2 KB per prekey — note in
the prekey budget.

### Handshake field (envelope JSON)

The initiator's **session-establishing message only** carries the ML-KEM
ciphertext as a new optional top-level envelope field:

```json
{
  "version": "veil-envelope-v3",
  ...
  "kemCt": "<base64url of the 1088-byte ML-KEM-768 ciphertext>"
}
```

`kemCt` is present only on the first frame of a session. It is **omitted** on
all steady-state messages.

### Session bootstrap delta

Outbound (initiator), replacing steps 1–3 of the legacy bootstrap:

1. Decode the recipient's PQ `signedPrekeyBundle`; verify `sig` over
   `x25519 || mlkem768`; extract both public keys.
2. Generate a fresh X25519 ratchet keypair. `ss_x = X25519(ratchetPriv, remoteX25519Pub)`.
3. `(kemCt, ss_k) = ML-KEM-768.Encaps(remoteMlkem768Pub)`. Put `kemCt` in the
   envelope's `kemCt` field.
4. `root_secret = HKDF-SHA256(ikm = ss_x || ss_k, salt = 0,
   info = "veil-pq-v3" || transcript_hash)` where `transcript_hash =
   SHA-256(remoteIdentityPub || ratchetPub || remoteX25519Pub ||
   remoteMlkem768Pub || kemCt)`. Classical secret is concatenated first;
   ordering is fixed and part of the test vectors.
5. Continue exactly as the legacy bootstrap from its step 5.

Inbound (responder), replacing steps 1–3 of the legacy bootstrap:

1. Extract `peerRatchetPub` from the first 32 bytes of the frame; read
   `kemCt` from the envelope.
2. `ss_x = X25519(localX25519Priv, peerRatchetPub)`.
3. `ss_k = ML-KEM-768.Decaps(localMlkem768Priv, kemCt)`.
4. Recompute `root_secret` with the same HKDF combiner and transcript hash.
5. Continue as the legacy bootstrap.

Security reduces to **"X25519 OR ML-KEM-768 holds"**: the combiner mixes
both secrets, so a break in either primitive leaves the root key as strong
as the other. The transcript binding makes KEM re-encapsulation and
classical/PQ downgrade detectable (a tampered `kemCt` or stripped prekey
changes `transcript_hash`, so both sides derive different roots and the
first GCM tag fails).

### Added verifiable invariants (proposal)

- The server still never holds any private key — the ML-KEM private key,
  like the X25519 and Ed25519 private keys, never leaves the device.
- `kemCt` is opaque ciphertext to the server; it reveals no key material.
- Harvest-now-decrypt-later: a recorded PQ session cannot be decrypted by a
  future CRQC unless it breaks ML-KEM-768 *and* X25519.
