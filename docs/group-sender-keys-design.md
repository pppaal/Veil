# Group sender keys — design

## Status

Design draft. **Not implemented**. External crypto review required before
merge. Current group chats use a single per-conversation symmetric key
shared across all members; this document covers the upgrade.

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
   detect it. (Today AD binds senderDeviceId, which mitigates the
   replay but not authorship in stronger threat models.)

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
groupSenderKey.envelope.version   = "veil-group-v1"
groupSenderKey.envelope.payload   = "g1." + b64u(payload)

payload (binary):
+--------+------------------+----------+----------------+
| 0x01   | senderDeviceId:16| ctr:u32  | AEAD ct + tag  |
+--------+------------------+----------+----------------+
```

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
  left_epoch    BIGINT,
  PRIMARY KEY (group_id, user_id)
);
```

`joined_epoch` records when a user is allowed to start decrypting.
`left_epoch` is set on removal.

## Protocol additions

```
POST /v1/conversations/:id/members        existing — emits group.epoch.bumped
DELETE /v1/conversations/:id/members/:uid existing — emits group.epoch.bumped
POST /v1/conversations/:id/key-distribute new endpoint:
  body: {
    epoch: number,
    distributions: Array<{ recipientUserId, encryptedChainKey, nonce, version }>
  }
  Server holds these blobs ephemeral with TTL=30 min, dispatches via
  1:1 message channel as a system message of messageType='system' with
  a special key-distribution body.
```

The key-distribution payload is itself a 1:1 ciphertext under the
existing ratchet — server cannot read the chain key.

## Migration strategy

Phase AB.1 — schema + epoch counter
  - migration adds current_epoch + group_member_epochs
  - server emits group.epoch.bumped on member churn (no-op clients
    ignore for now)

Phase AB.2 — opt-in flag
  - new `group_use_sender_keys` field on conversation, default false
  - clients that set the flag negotiate sender keys; others stay on
    the shared key

Phase AB.3 — clients implement
  - mobile first (already has Ed25519 + ratchet primitives)
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
3. Skipped-key cap of 1000 per peer — sound for 25-member groups
   under intermittent connectivity?
4. Server learns groupEpoch — is that an acceptable metadata leak?
5. Sender signing key separate from identity key vs derived — does
   ratcheting the signing key add meaningful PCS?
6. Ed25519 vs HMAC for authorship — does the public-verify property
   matter to us, or is HMAC simpler?

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
