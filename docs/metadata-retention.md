# Server-side metadata retention

VEIL's threat model promises the server keeps as little as possible. Message
bodies are always ciphertext, but delivery leaves operational metadata behind:
who called whom, who read what when, which blobs belong together. This
document is the per-table answer to "how long does the server keep it?". The
field-level answer, generated from the schema's `@privacy` annotations and
checked in CI, is [What a seized VEIL server reveals](server-data-inventory.md).

## How retention is enforced

`RetentionService` (`apps/api/src/modules/retention/`) is the **only** place
that schedules sweeps. It runs shortly after boot and then every 10 minutes.

- **One sweeper at a time.** Every batch runs in its own `prisma.$transaction`
  that first calls `SELECT pg_try_advisory_xact_lock(hashtext('veil-retention'))`.
  The lock is transaction-scoped, so it is released with the transaction and
  works behind a connection pooler. If another API instance holds it, the tick
  is skipped (`retention.lock_held`) and that instance does the work.
- **Bounded batches.** A batch selects at most 1000 ids; each sweep runs at most
  20 batches per tick. The cap is per sweep, so a backlog in one table (say,
  expired messages after downtime) cannot starve the sweeps after it. Anything
  left over is picked up on the next tick, and a tick that is still running
  when the next one is due is not started twice.
- **Counts only.** One `retention.swept` line per tick with a count per sweep
  and the number of attachment blobs deleted. A failed sweep logs
  `retention.sweep_failed` with the sweep name and the error class or Prisma
  code, never the error message (it can quote query arguments) and never ids.
- **No storage calls inside a transaction.** A batch only touches the
  database: it deletes its messages (or selects its orphans) and commits. The
  blobs it released are deleted afterwards, so a slow or unreachable bucket
  can delay blob cleanup but never the message deletes, and never holds the
  lock or row locks. Each storage attempt times out after 10 seconds.
- **Blob before row.** An attachment blob is deleted from object storage
  first; the row is removed only once the blob is gone, and only if nothing
  started referencing it meanwhile. If the storage call fails the row stays,
  and the orphan sweep retries it on a later tick, so ciphertext is never left
  in storage with nothing pointing at it. When a whole group of deletes fails,
  storage is treated as unavailable for the rest of the tick
  (`retention.storage_unavailable`, with the error class only).
- Every sweep is marked `// @retention-sweep <Model>` in the source, and
  `scripts/schema-privacy-check.mjs` fails CI when a model whose fields carry
  a timed retention has no such marker.

## Retention matrix

| Table | What it holds | Kept for | Enforced by |
| --- | --- | --- | --- |
| `messages` | Ciphertext envelopes and routing metadata, reactions included (they are encrypted messages with `messageType` `reaction`) | Until `expiresAt` (disappearing timer), and **never more than 30 days** after `serverReceivedAt` (`VEIL_MESSAGE_MAX_AGE_DAYS`, default 30; 0 disables the cap, and production refuses to boot outside 1 to 30), delivered or not. View-once rows are deleted on first read. | `RetentionService` (`expiredMessages`, `agedMessages`); `MessagesService` (view-once) |
| `attachments` + object storage | Encrypted blob, its size and sha256 | When a sweep deletes the last visible message that references it, blob and row are deleted as soon as that batch commits. Orphans — pending, failed, or uploaded but referenced by no message or only by delete-for-everyone tombstones (this covers view-once consumption and delete for everyone) — are deleted 24 hours after upload. All blobs of an account are deleted on account deletion. Download tickets are issued only for a live message in a conversation the requester belongs to. | `RetentionService` (message sweeps, `orphanAttachments`); `AccountService` |
| `message_receipts` | Per-recipient delivered/read timestamps | Read receipts: 7 days after `readAt`. Unread: 30 days after `deliveredAt`. Always deleted with their message. | `RetentionService` (`receipts`) |
| `stories` | Encrypted story envelope and its format | 24 hours. | `RetentionService` (`expiredStories`) |
| `story_audiences` | Who a story is addressed to | Deleted with their story. | `RetentionService` (`expiredStories`) |
| `story_views` | Who viewed which story | Deleted with their story. | `RetentionService` (`expiredStories`) |
| `call_records` | Who called whom, when, how long | A call still ringing after 90 seconds becomes `missed`; a call still active after 12 hours becomes `ended`. Terminal calls are deleted after `VEIL_CALL_RECORD_RETENTION_DAYS` (default 30; 0 keeps them, and production refuses to boot outside 1 to 30). | `RetentionService` (`missedCalls`, `endedCalls`, `callRecords`) |
| `abuse_reports` | Reporter, reported user, reason | 90 days. There is no note column: a free-text note from an older client is accepted and dropped. | `RetentionService` (`abuseReports`); `SafetyService` |
| `one_time_prekeys` | Public X3DH one-time prekeys | Unconsumed: until claimed or the device is deleted. Consumed: `VEIL_PREKEY_CONSUMED_RETENTION_DAYS` (default 30; 0 keeps them) so a keyId is never reused mid-flight. | `RetentionService` (`consumedPrekeys`) |
| `secret_blobs` | One-time link ciphertext | Deleted on first read; unopened links are deleted at `expiresAt`. | `SecretService`; `RetentionService` (`secretBlobs`) |
| `device_transfer_sessions` | Transfer token hash, old device, expiry, and the new device a completed transfer created (so a retried completion whose first answer was lost gets the same answer) | Closed after the transfer TTL (default 300 s); deleted with their old device (below) or with the account. | `DeviceTransferService`; `RetentionService` (`revokedDevices`); `AccountService` |
| `devices` | Public identity, prekey and auth keys, push token, label, last-seen and last-sync days | Active devices: until revoked or the account is deleted. Revoking a device (or transferring away from it) replaces its label with "Removed device" and deletes its push token, unclaimed one-time prekeys and sync cursors at once; the row itself is deleted once it has been revoked for 30 days and no message, attachment or call record references it any more. `lastSeenAt` and `lastSyncAt` hold the start of the UTC day only and are written at most once a day, so they do not form an activity timeline. | `revokeDevice` (`DevicesService`, `DeviceTransferService`); `RetentionService` (`revokedDevices`); `AccountService` |
| `users`, `user_contacts`, `user_blocks`, `conversation_mutes` | Handle and social graph (no display names, profile text or contact nicknames) | Account lifetime. A deletion that stops part-way leaves the account revoked; the server finishes it within about an hour (`AccountDeletionResumer`), since the user's tokens no longer authenticate. | `AccountService` |
| `retired_handles` | Peppered HMAC of a deleted account's handle | 90 days after the account is deleted; until then the handle cannot be registered again. | `AccountService` (insert); `RetentionService` (`retiredHandles`) |
| `conversations`, `conversation_members`, `device_conversation_states`, `group_metas`, `channel_metas`, `group_member_epochs` | Current membership, the epoch each group member joined at, and per-device sync and read cursors (conversation orders, no timestamps) | Conversation or account lifetime. Leaving a group or channel, or being removed, deletes the member's membership, epoch row, sync cursors and mute for that conversation, so former members are not kept. `group_metas.created_by_user_id` names the group's current owner (ownership transfer moves it), so it never names a former member, and deleting an account deletes the groups and channels it currently owns, not ones it once created. A direct conversation's dedupe key names both members; it is cleared when either deletes their account, and a direct conversation left with no members is deleted. | `GroupsService`, `ChannelsService`, `AccountService`, conversation deletion |

### Short-lived keys in the ephemeral store (Redis)

Production Redis (`docker-compose.prod.yml`) keeps no append-only file. An
append-only file would hold every write, with its absolute expiry time, until
a rewrite that by default waits for 64 MB, so the keys below would stay
readable on disk for weeks after they expired. Redis instead writes an RDB
snapshot of the keys alive at that moment, within a minute of any write and
on shutdown, and each snapshot replaces the last. The snapshot file therefore
holds the keys that were alive at the last snapshot, not a history of expired
ones; a replaced snapshot can still linger in the disk's free blocks (see "No
database backups" below). On a server that has gone idle, the last snapshot
stays until the next write replaces it, so a key in it can outlive its TTL
until then.

### No database backups

The production stack runs no database dump, base backup or snapshot of the
Postgres volume, and the deployment guides set none up: a dump would keep
deleted accounts and handles, burned one-time links, expired and view-once
ciphertext, receipts and the social graph past every window in this document,
on the host and wherever it is copied. `scripts/policy-check.mjs`
(`no-database-dumps`) fails CI when a compose file or anything under `infra/`
runs a dump tool. The only dump the runbook mentions is the one taken right
before an upgrade that cannot be rolled back otherwise, which the operator
deletes as soon as the upgrade is verified (`vps-deploy-runbook.md` 8.1).

No dump does not mean a seized volume holds only the current rows. Deleting
a row does not wipe it from the disk: Postgres leaves the bytes of deleted
rows in its write-ahead-log segments (`pg_wal`) and in table and index pages
until it happens to reuse that space. A WAL segment keeps its bytes until
Postgres has written past it and removed it or overwritten it on reuse, and
freed space in a page keeps them until a new row lands there or the table is
rewritten, so this follows no schedule and on a quiet server can take days.
`apps/api/test/unit/database-residue-postgres.spec.ts` shows it on a real
Postgres: after `DELETE`, `VACUUM` and `CHECKPOINT`, a burned one-time link's
ciphertext is still in `pg_wal` and in the `secret_blobs` table file. Until
the space is reused, a seized volume can also hold rows that were deleted or
swept before the seizure: burned one-time links (whoever also has the link
can decrypt one), expired and view-once message ciphertext, receipts, and the
handles and social graph of deleted accounts. Files deleted on the host, such
as a Redis snapshot that a newer one replaced or an attachment blob deleted
from the MinIO volume, likewise stay in the filesystem's free blocks until
the filesystem reuses them. Encrypting the volumes with a key that is not
kept on the host keeps this residue from someone who takes a powered-off
disk; the deployment guides do not set that up.

### Database and container logs

Postgres runs with `log_error_verbosity=terse`, so a logged error carries no
DETAIL line: a unique violation does not log the conflicting key (both user
ids of a direct conversation, a handle), and statements are logged with their
`$n` placeholders only. Every production container logs to Docker's
`json-file` driver capped at three 10 MB files, so a container log is
overwritten as it grows rather than kept until the container is removed. See
`observability-hygiene.md`.

| Key | Kept for | What it links |
| --- | --- | --- |
| `veil:thr:*` (and `…:blocked`) | The rate-limit window, 60 seconds | A request count per route and client. The key is an unkeyed SHA-256 of the route and the client: `ip:<address>` on routes that need no sign-in, `dev:<deviceId>` on the others. Hashing every IPv4 address recovers the client's address in roughly 80 to 100 minutes on one CPU core. |
| `budget:*` | 1 hour | Key-directory budgets. The key holds a SHA-256 digest of who looked up whom instead of the ids. The digest is unkeyed, so someone who also holds the database ids can test a guessed pair; the one-hour expiry, with the snapshot caveat above, is what limits it. |
| `auth:challenge:*`, `auth:challenge-index:*` | `VEIL_AUTH_CHALLENGE_TTL_SECONDS` (default 120 seconds) | A pending sign-in or step-up challenge and the device it was issued to. Taken on use; removed on account deletion. |
| `auth:refresh:*`, `auth:refresh-family:*`, `auth:refresh-families:*` | Until a UTC midnight 31 days after the day of the last refresh (at least 30 days) | The SHA-256 of a refresh token (never the token), with the user id, device id and token family it belongs to. Removed on rotation, logout, reuse detection and account deletion. The expiry is set to a UTC midnight, not to "now + 30 days", so it records the day of the last refresh and not its time, like `devices.lastSeenAt`. A refresh token carries its family id, so a replayed old token is recognised without a record per rotation. |
| `auth:rotated:*` | Until a UTC midnight, at most 31 days | Only for refresh tokens issued before tokens carried their family id: the family a rotated one belonged to, so its replay is still caught. One per pre-upgrade session at most; none is written for a newer token, so the last expires 31 days after the upgrade. It names no user or device. |
| `auth:blacklist:*` | Until the access token would expire (at most 1 hour) | The id of a logged-out access token, with its user and device ids. |
| `group:keydist:*` | 30 minutes | A sealed Sender Keys chain-key distribution, addressed by conversation, epoch and the sending and receiving user and device. The server cannot open it; see `group-sender-keys-design.md`. |
| `transfer:claim:*` | Transfer TTL | The first claim of a device-transfer session: the new device's label, platform and public keys. See `device-transfer-flow.md`. |

## Directory privacy

The key directory follows the same minimisation:

- `GET /v1/keys/:handle` needs a signed-in device and allows 10 requests per
  minute per client, like `GET /v1/users/:handle`, so the handle namespace
  stays slow to enumerate. There is no anonymous key lookup: the old public
  `GET /v1/users/:handle/key-bundle` is gone. One-time prekeys are claimed
  atomically in one transaction, at most 20 per hour per (requester device,
  target user) and 50 per hour per target device. Over budget, the lookup still succeeds but
  returns no one-time prekey and consumes nothing.
- `GET /v1/keys/group/:conversationId` serves the same entries for every other
  member of a group, only to a current member of that group (anyone else gets
  404), at 20 requests per minute per device. It claims nothing, so it spends
  no budget and cannot drain a pool; it reveals nothing a member cannot
  already learn from the member list and per-handle lookups.
- `GET /v1/users/:handle` needs a signed-in device and returns only id, handle
  and status. Profiles hold no text until encrypted profiles ship, so
  `GET /v1/profile/:handle` answers 410 `profile_e2e_pending`.
- A story goes only to the audience its author picked, every member a mutual
  contact neither side has blocked; outside that audience it answers like a
  missing story.

## Relationship to other tracks

Retention limits how long the server *keeps* the metadata it sees. Hiding the
sender from the server in the first place is the job of sealed sender, which
is under revision: the current design does not hide the sender
(`sealed-sender-design.md`).
