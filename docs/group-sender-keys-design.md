# Group sender keys — design

## Status

**Phase AB.3 (mobile) implemented — pre-audit.** The client crypto lives in
`apps/mobile/lib/src/core/crypto/group_sender_keys.dart` (engine + sealer,
pure Dart, covered by `test/group_sender_keys_test.dart` for the test matrix
below and `test/group/group_sender_keys_replay_test.dart` for distribution
freshness) and is wired into the app through
`apps/mobile/lib/src/features/conversations/data/group_sender_key_coordinator.dart`
(distribution, offline pickup, epoch bumps; controller-level tests with three
real members on a fake relay, plus `test/group/group_coordinator_hardening_test.dart`
for a hostile relay and directory). New groups created from the mobile app
set `useSenderKeys: true`; groups created by older clients stay on the
shared-key path. External crypto review is still required before any of this
is called "secure" — see "What the implementation decided" for the places a
reviewer should look first.

### What the implementation decided (deviations from the draft below)

1. **Distribution channel is identity-sealed, not 1:1-ratchet-wrapped.**
   VEIL's ratchet sessions are keyed per *conversation*, so two group members
   need not share one. Each distribution blob is instead sealed to the
   recipient's signed X25519 prekey (ephemeral X25519 → HKDF-SHA256 →
   AES-256-GCM, bundle signature verified against the recipient's Ed25519
   identity exactly like 1:1 bootstrap) and **signed by the sender's Ed25519
   identity key**, which the recipient fetches from the directory — never
   from the blob. Blob AD binds `groupId || epoch || senderDeviceId ||
   recipientUserId`. Not forward-secret on its own; mitigated by the chain
   key dying at the next epoch and the relay's 30-minute TTL. Production
   Redis keeps no append-only log, so no Redis file keeps an expired blob;
   only a snapshot of the keys alive when it was taken does, and a replaced
   snapshot can linger in the disk's free blocks until they are reused (see
   `metadata-retention.md`). Reviewer question #7. Since `veil-gkd-v2` the blob also carries signed freshness
   metadata; see "Distribution freshness" below.
2. **Frame layout** (`veil-group-v1`, see "Wire shape"): the epoch and a
   64-byte Ed25519 signature travel *in the frame*, so a receiver can route
   and authenticate without trusting server-supplied metadata. Signature
   covers `AD || nonce || ciphertext`. Signing key is a **per-epoch Ed25519
   key generated with the chain** and distributed alongside it (question 5
   → "separate, rotated with the chain").
3. **Own frames are self-decryptable.** The sender registers its own chain as
   a peer so history fetched back from the server decrypts after a restart.
4. **Stale-epoch sends are not retried.** The outbox holds ciphertext only, so
   a frame rejected with `group_epoch_stale` is marked failed and the user
   re-sends under the new epoch (the next send re-keys automatically).
5. **Cache schema 8** stores the envelope version per message so group frames
   survive a cold start without being misrouted to the 1:1 ratchet.
6. Pickup is attempted once per `(group, epoch)` per undecryptable frame to
   keep a flood of unknown frames from hammering the relay; a realtime
   `group.key.distribution` or explicit sync resets the attempt.
7. **The relay and directory are not trusted to pick recipients.** The
   coordinator seals only to a member's *active* device as listed for that
   member's own userId; if that device is missing it never falls back to
   another listed bundle. The engine records with our own chain, and
   persists with it, which members the chain has been uploaded to; every
   other member is handed it on the next send, after a restart too (an
   epoch bump re-keys and so reaches everyone anyway). A member already
   recorded is never sent the chain again: the relay would replace the copy
   still buffered for them with one starting at a later counter, and an
   offline member would lose the frames in between. A member reached late
   reads from the counter at which they were reached; earlier frames stay
   unreadable to them.
   A member is skipped this way, and the rest of the round still goes out,
   whenever the reason is about that member alone: the directory has no
   active device for them (an entry without one, or a 404
   `active_device_not_found`, e.g. mid account deletion or after their last
   device was revoked), their signed prekey does not verify
   (`recipientBundleInvalid`), or the trust hook refuses or cannot judge
   their identity. A failure that is not about the member (offline,
   throttling, a server error) aborts the round. While nobody is recorded
   as holding the chain that fails the send, because the frame could
   otherwise go out unreadable to everyone; once someone holds it, the send
   goes ahead and whoever was not reached is tried again on the next send.
8. **Attachments come only from the authenticated payload.** A frame's
   attachment pointer is read from the decrypted inner payload (long-key or
   the 1:1 adapter's short-key form); the outer envelope's attachment, which
   the server controls, is never used. Nor does the outer `messageKind`
   decide rendering: a frame with an unknown inner kind, and the placeholder
   for a frame that does not decrypt, both render as text.
9. **The server does not decide the mode once a device has seen it.** The
   `useSenderKeys` flag is set at creation and the server refuses to clear
   it (`sender_keys_irreversible`), but a lying relay could still list the
   group without it. A device therefore pins Sender Keys mode in its
   keystore the first time the group is listed with it or a `veil-group-v1`
   frame authenticates in it; from then on a listing without it is
   overruled with a local notice, sends never reach the pairwise engine and
   pairwise frames in the group are `downgrade_rejected`
   (`crypto-envelope-spec.md`, version pinning). A device that has never
   seen the group in Sender Keys mode still follows the listing.
10. **One directory request per distribution round.**
   `GET /v1/keys/group/:conversationId` returns every other member's
   directory entry with the epoch they belong to, so a round no longer costs
   one `GET /v1/keys/:handle` per member (see "Protocol additions").

**Phase AB.1 (server-side epoch bookkeeping) has shipped.** The server now
maintains `conversations.current_epoch`, records the epoch at which each
current member joined in `group_member_epochs` (`joined_epoch`; the row is
deleted when the member leaves or is removed, so the table never lists former
members), bumps the epoch on every join/leave/remove, and fans a
`group.epoch.bumped` realtime event to the remaining members. No key material is involved — this is pure scaffolding
that the client crypto (phases AB.3+) will consume once it lands. Clients that
don't implement Sender Keys yet ignore the event, so the change is a no-op for
the current shared-key behaviour.

## Distribution freshness (`veil-gkd-v2`)

The relay sees every sealed distribution and may record it. Before v2, a
re-delivered blob overwrote the recipient's chain: the server could rewind a
sender's chain and replay frames already consumed, or re-deliver a
pre-rotation blob and reinstall a chain and signing key the sender had
retired.

* **Generation.** Every chain a member creates in an epoch gets a
  `generation`: 1 for the first, +1 for each rotation (`forceRotate`) or new
  own key. It is persisted with the own chain.
* **Sealed payload.** The encrypted payload gains `generation` and
  `issuedAtMs` (the sender's clock at sealing). The sealing construction is
  unchanged; the AD becomes
  `"veil-gkd-v2" || lp(groupId) || u32(epoch) || lp(senderDeviceId) || lp(recipientUserId)`
  and the sender's identity signature covers
  `AD || u32(generation) || u64(issuedAtMs) || u32(startCounter) || ephPub || nonce || ciphertext`.
  Because generation, issue time and start counter travel inside the
  ciphertext, v2 decrypts first and verifies the signature before any
  payload field is trusted; no engine state is touched until both pass.
* **Ledger.** Per `(groupId, epoch, senderDeviceId)` the engine persists
  `{signingPub, generation, highWaterConsumed}`, where `highWaterConsumed` is
  the highest counter whose key has left the chain. The entry outlives the
  chain itself (`dropPeer`) and is discarded only with the epoch.
* **Ingest rules** (`GroupSenderKeyEngine.ingestDistribution`):
  * no ledger entry: accept v1 or v2;
  * a v1 (`veil-gkd-v1`) blob never replaces an entry (`distribution_stale`);
  * same signing key and generation: never rewind — a no-op, except that a
    chain removed by `dropPeer` is reinstalled when the blob starts above
    `highWaterConsumed`. While the chain is still installed, even a blob
    that starts further ahead is a no-op: otherwise the relay could replay a
    later blob of the same chain to skip a receiver past frames still in
    flight. The cost is that a receiver more than 2000 frames behind
    (`tooFarAhead`) is only moved forward by a rotation or an epoch bump;
  * higher generation: replaces the chain only if `issuedAtMs` lies within
    [now − 30 min, now + 5 min] (the relay TTL, plus clock skew);
  * lower generation, or a different signing key at the same generation:
    rejected (`distribution_stale`).
* **Epochs only move forward.** `resetForEpoch` ignores a bump to an epoch
  already held or an older one, and `ensureOwnSenderKey` refuses an older
  epoch (`epochMismatch`), so a server-supplied stale epoch cannot wipe the
  current chains and re-open an old epoch's recorded distributions. The
  cost is liveness: an epoch the server announces before it reaches it (a
  bug, or a hostile relay) stalls sends to that group with `epochMismatch`
  until the server's epoch catches up, where previously the next correct
  epoch healed it.
* **Skipped keys** carry their insertion time and expire after 7 days
  (purged whenever the group is decrypted and on restore), capped at 200 per
  sender chain and 1000 per group, oldest evicted first.
* **Serialization.** Every mutating engine call on a group
  (`ensureOwnSenderKey`/rotation, `encrypt`, `decrypt`, `ingestDistribution`,
  `recordDelivered`, restore, reset, drop, forget) runs under a per-group
  async lock (`core/util/keyed_async_lock.dart`) and returns only after the
  persister has stored the new state, so concurrent decrypts cannot commit
  from the same base and rewind each other.
* **Snapshots** moved to schema 2. Schema-1 snapshots are dropped, never
  migrated. Our next send re-keys at generation 1, which peers accept over
  the legacy entry they hold for us. Peers' chains are *not* recovered from
  the relay, which keeps blobs for only 30 minutes, and a peer does not
  resend a chain it has already delivered: a peer that re-keyed before we
  upgraded stays unreadable to us until it rotates or the epoch moves, its
  frames showing as awaiting a sender key. A migration would need an extra
  ledger rule (a legacy entry and the same signer's first v2 blob describe
  one chain, which must not move backwards), not worth its risk for a
  pre-release format. Schema-2 snapshots written before the delivery record
  existed restore with nobody recorded, so that chain is handed to every
  member once more.

Known liveness costs, accepted for now: a frame of the old generation that
arrives after its sender's rotation no longer verifies; and a member that
loses its group state (including a snapshot that fails to parse, which
restore drops) restarts at generation 1 with a new signing key, which peers
reject until the next epoch bump.

## Trust hook (`trustCheck`)

`GroupSenderKeyCoordinator` takes an optional
`trustCheck(userId, deviceId, identityPublicKey) -> Future<bool>`. It is
consulted with the directory identity before sealing our chain to a
member's device (false: skip, ask again on the next send) and before
accepting a distribution signer (false: reject with `untrusted_identity`).
It fails closed: a check that throws counts as false. Null allows every
directory identity, which is today's behaviour. On the receiving side, a
distribution whose sender the directory cannot serve right now is not
installed and stays on the relay for the next pickup. The intended
implementation is the TOFU resolver in `core/identity/`
(`TrustedIdentityResolver.evaluate(...).isTrusted`): first sighting of a user
pins silently, while a changed key or a new device of a known user is never
accepted without the user's approval.

## Why

Today VEIL handles 1:1 chats with the double ratchet (mobile) or v2
single-shot ECDH (web). Groups skip the ratchet entirely: every member
encrypts to the same conversation key, derived once when the group was
created and never rotated.

Failure modes:

1. **No forward secrecy on join.** A new member who later turns
   compromised can read messages from before they joined, because the
   conversation key has not changed.
2. **No post-compromise security.** A leaked key reads everything past
   and future until the group is recreated.
3. **No member revoke.** Removing a member from `conversation_members`
   blocks new sends from being delivered to them, but they retain the
   key from any cached past messages and can decrypt every future
   message they observe (e.g. via a colluding insider or a server
   exfiltration). The trust model degrades silently.
4. **Authorship is implicit.** The conversation key alone does not bind
   a sender — a member could replay another member's ciphertext under
   their own deviceId and the receiver has no cryptographic way to
   detect it. (Note: the 1:1 AEAD path **does** now bind `senderDeviceId`
   — along with the ratchet public key and message counter — as associated
   data, as of mobile adapter `lib-x25519-aes256gcm-v3`; see
   `crypto-envelope-spec.md` → "AEAD associated data (header binding)". That
   AAD binding authenticates the 1:1 header fields, but it does **not** by
   itself give the *group* authorship guarantee described here: in a group,
   every member holds the shared sender key, so binding `senderDeviceId` to a
   ciphertext a member produced does not stop a *different* member from
   re-encrypting content under their own key/header. Per-sender Ed25519
   signatures (below) are still required for cryptographic group authorship.)

Signal's "Sender Keys" pattern fixes all four. We adopt it.

## Goals

1. **Forward secrecy within each member's chain** — past messages stay
   private even if a member's current state leaks
2. **Member revoke** — removing a member from the group invalidates
   every future ciphertext for them, no read access on future messages
3. **Authorship** — a message is cryptographically tied to one specific
   member's signing key; replay under a different identity fails
4. **Single-pass send** — sender encrypts once, server fans out the
   same ciphertext to every member, no per-recipient envelope
5. **Backward compat** — existing 1:1 ratchet stays; groups upgrade
   independently

## Non-goals

- Federated groups across multiple servers
- Anonymous groups (sender visibility is part of the model)
- Decentralized membership (server remains source of truth)

## Wire shape

Sender Keys produces a single ciphertext per send. Wire envelope adds:

```
envelope.version    = "veil-group-v1"
envelope.ciphertext = b64u(frame)
envelope.nonce      = b64u(12 random bytes)

frame (binary, as implemented):
+------+--------+--------------------+-----------+---------+--------+----------------+
| 0x01 | len:u8 | senderDeviceId:utf8| epoch:u64 | ctr:u32 | sig:64 | AEAD ct + tag  |
+------+--------+--------------------+-----------+---------+--------+----------------+
```

(The draft below assumed a 16-byte UUID sender id; device ids are
length-prefixed UTF-8 in the implementation so non-UUID ids in tests and
future id schemes stay valid.)

`senderDeviceId` is the truncated UUID of the sender's device (16 bytes
of the 16-byte UUID — full id, no truncation needed). `ctr` is a
per-(senderDeviceId, group) message counter. AEAD-AD binds:

```
AD = "veil-group-v1"
   | groupId
   | senderDeviceId
   | ctr (4 bytes BE)
   | groupEpoch (8 bytes BE)
```

`groupEpoch` is incremented on every membership change (see "Member
churn" below).

## Per-member state

Each member holds, per group:

```
{
  groupId,
  groupEpoch,                       // incremented on join/leave
  myChainKey,                       // mine — used to derive per-message keys
  myCounter,                        // matches ctr in wire
  myEd25519SignaturePub,            // for sender authentication on the wire
  peers: {
    [senderDeviceId]: {
      chainKey,                     // their chain key
      counter,                      // last accepted ctr
      ed25519SignaturePub,          // their signing pub for verify
      skippedKeys: { "<ctr>": "<keyB64>" }  // out-of-order tolerance
    }
  }
}
```

The chain key advances per send: `chainKey_{n+1} = HKDF(chainKey_n,
salt=[0x02], info="veil-gck-v1")`.

Per-message key:
```
mk_n = HKDF(chainKey_n, salt=ctr-bytes, info="veil-gmk-v1", L=32)
```

Sender signs the AEAD output with Ed25519 over `(senderDeviceId, ctr,
groupEpoch, ciphertext)` and prepends the signature to the wire payload
(or attaches via a separate envelope.signature field — TBD by review).

## Member churn (epoch bumps)

### Join

Existing members must hand the new member their chain keys at the
new member's join boundary so the new member can decrypt messages from
the moment they joined. Two options:

**Option A — full epoch reset.** On any join or leave, every existing
member generates a fresh chainKey, stamps the new groupEpoch, and
distributes their new chainKey to all other members via 1:1 ratchet
sessions. Messages from before this epoch remain decryptable only by
the original recipients (forward secrecy preserved on join).

**Option B — additive distribution on join, full reset on leave.**
Existing members keep their chains across joins; new member receives
each existing member's current chainKey + counter via 1:1. Leaves
trigger Option A.

We pick **Option A** for both. Symmetry simplifies the protocol and
the every-event reset gives strong PCS even when the server attempts
to suppress epoch bump signals.

Cost: each join/leave triggers `(N-1)` 1:1 ratchet sends of size
~64 bytes (chainKey + counter + epoch). Fine up to ~50 members; the
private-beta cap is 25.

### Leave

Removed member's chainKey is no longer trusted. Server publishes a
`group.epoch.bumped` realtime event with the new epoch. Existing
members:

1. Discard any chainKey for the removed member.
2. Generate a fresh own chainKey.
3. Encrypt the fresh key for every remaining member via 1:1.
4. Increment groupEpoch.

The removed member's existing decrypted messages remain decrypted (we
cannot un-decrypt them locally), but no future ciphertext on the new
epoch will be decryptable to them.

### Server's role

The server tracks `groups.current_epoch`, validates that an inbound
message's epoch matches the current epoch, and rejects with
`group_epoch_stale`. That's the only crypto-relevant gate the server
needs; all key material remains client-side.

## Database schema (additive)

```sql
ALTER TABLE conversations ADD COLUMN current_epoch BIGINT NOT NULL DEFAULT 0;

CREATE TABLE group_member_epochs (
  group_id      UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_epoch  BIGINT NOT NULL,
  PRIMARY KEY (group_id, user_id)
);
```

`joined_epoch` records when a user is allowed to start decrypting. The row is
deleted on leave or removal (migration 0019 dropped the never-read
`left_epoch`), so only current members have one.

## Protocol additions

```
POST /v1/conversations/group/:id/members        existing — emits group.epoch.bumped
DELETE /v1/conversations/group/:id/members/:h   existing — emits group.epoch.bumped
POST /v1/conversations/group/:id/key-distribute ✅ SHIPPED:
  body: {
    epoch: number,
    distributions: Array<{ recipientUserId, encryptedChainKey, nonce, version }>
  }
  Guards: caller must be a current member, the group must have
  group_use_sender_keys enabled, epoch must equal current_epoch
  (else group_epoch_stale), and every recipient must be a current
  member other than the sender (else key_distribution_invalid).
  The server buffers each blob ephemerally (Redis, TTL=30 min, keyed
  per conversation/epoch/recipient/sender so redistribution within an
  epoch is an idempotent overwrite) and fans out a
  group.key.distribution realtime event to each recipient.
GET /v1/conversations/group/:id/key-distributions ✅ SHIPPED:
  Offline-pickup path: returns every still-buffered blob addressed to
  the caller for the group's current epoch. Non-consuming; blobs
  disappear on TTL expiry or epoch bump, after which the recipient
  asks senders to redistribute.
GET /v1/keys/group/:conversationId ✅ SHIPPED:
  The key directory of the group for one distribution round:
  { conversationId, epoch, members: KeysResponse[] }, one entry per
  current member other than the caller, devices as GET /v1/keys/:handle
  serves them. Members and epoch are read in one snapshot. Nothing is
  claimed (oneTimePrekey is always null) and no directory budget is
  spent, so a round costs one request instead of one handle lookup per
  member, which the 10/min handle limit could not sustain. 20 requests
  per minute per device; anything but a current member of a group gets
  404 group_not_found.
```

The key-distribution payload is itself a 1:1 ciphertext under the
existing ratchet — server cannot read the chain key. (The earlier
draft dispatched via a 1:1 system message; the shipped shape uses a
dedicated realtime event plus the TTL buffer instead, which keeps key
material out of the durable messages table entirely.)

## Migration strategy

Phase AB.1 — schema + epoch counter ✅ SHIPPED
  - migration 0013 adds conversations.current_epoch + group_member_epochs
  - GroupsService bumps the epoch and records (on join) or deletes (on
    leave) the member's epoch row atomically on createGroup / addMember /
    removeMember / leaveGroup
  - server emits group.epoch.bumped to remaining members on churn (no-op
    clients ignore for now); the removed member is deliberately excluded
  - the inbound-message `group_epoch_stale` gate is intentionally deferred:
    enabling it before clients send an epoch would reject every group send,
    so it lands with AB.2 behind the opt-in flag

Phase AB.2 — opt-in flag ✅ SHIPPED
  - new `group_use_sender_keys` field on conversation, default false
  - clients that set the flag negotiate sender keys; others stay on
    the shared key
  - server-side key-distribution relay (POST key-distribute + GET
    key-distributions + group.key.distribution event) shipped with it;
    the blobs it relays stay opaque so no crypto-review dependency

Phase AB.3 — clients implement
  - mobile ✅ IMPLEMENTED (pre-audit): engine, sealer, coordinator, cache
    schema 8, realtime handlers; v2 distributions with freshness and the
    trust hook
  - web demo second (after envelope v3 lands — Phase W)

Phase AB.4 — required flip
  - new groups default to sender keys after a deprecation window (~60
    days)
  - old groups stay on shared key until next epoch bump or manual
    upgrade

## Test matrix

| # | Scenario | Expected |
|---|---|---|
| 1 | 3-member group, alice sends, bob+carol decrypt | ok |
| 2 | dave joins, alice sends post-join | dave decrypts (alice key was redistributed) |
| 3 | dave joins, bob's pre-join messages | dave cannot decrypt (FS preserved) |
| 4 | dave leaves, alice sends | dave cannot decrypt (server filters + key rotated) |
| 5 | dave leaves, dave replays old ciphertext from before leave | bob+carol decrypt as before |
| 6 | dave leaves, dave forges new ciphertext under his old chainKey | every recipient rejects with epoch mismatch |
| 7 | server omits group.epoch.bumped event | clients self-heal via /conversations/:id polling |
| 8 | alice's chainKey leaks | only future-sent messages decryptable; past ones not |
| 9 | bob attempts to send under alice's signing key | every recipient rejects authorship signature |
| 10 | out-of-order delivery (alice sends 1,2,3, server reorders 2,1,3) | all decrypt via skipped-key cache |

## External review questions

1. Is Option A (full reset on every churn) preferable to Option B
   under our threat model?
2. Is the AD construction sufficient — specifically, does omitting
   `recipient` allow cross-conversation replay?
3. Skipped-key caps of 200 per sender chain and 1000 per group with a
   7-day TTL — sound for 25-member groups under intermittent connectivity?
4. Server learns groupEpoch — is that an acceptable metadata leak?
5. Sender signing key separate from identity key vs derived — does
   ratcheting the signing key add meaningful PCS?
6. Ed25519 vs HMAC for authorship — does the public-verify property
   matter to us, or is HMAC simpler?
7. Distribution sealing is identity-bound (ephemeral X25519 to the signed
   prekey + sender Ed25519 identity signature) rather than ratchet-wrapped.
   Is the loss of forward secrecy on the *distribution* acceptable given
   the per-epoch chain lifetime and 30-minute relay TTL, or must the sealer
   be moved onto a per-device 1:1 session?
8. Distribution freshness relies on the sender's clock (`issuedAtMs`) only
   when a newer generation replaces a chain. Is the [now − 30 min, now + 5
   min] window, with no freshness requirement for a first install, the right
   trade-off against offline pickup?

## Cost estimate

| Phase | Effort | Risk |
|---|---|---|
| AB.1 schema + epoch | 2d | low |
| AB.2 opt-in flag plumbing | 1d | low |
| AB.3 mobile sender keys | 5-7d | medium — new crypto path |
| AB.3 web sender keys | 5-7d | medium — needs envelope v3 first |
| External review | 4-6w wall clock | external |

Total client-engineering: ~12-15 days. Wall-clock with audit:
~10-14 weeks.

## Decision required before AB.1 starts

1. Confirm Option A (full reset on every churn) vs Option B.
2. Confirm signing-key model: separate Ed25519 vs derived from
   identity vs HMAC.
3. Confirm AD field set.
4. Confirm key-distribution channel: dedicated endpoint vs message-
   typed system message vs out-of-band.
