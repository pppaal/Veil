# Server-side metadata retention

VEIL's threat model promises the server keeps as little as possible. Message
bodies are always ciphertext, but delivery leaves operational metadata behind:
who called whom, who read what when, which blobs belong together. This
document is the per-table answer to "how long does the server keep it?".

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
- Every sweep is marked `// @retention-sweep <Model>` in the source.

## Retention matrix

| Table | What it holds | Kept for | Enforced by |
| --- | --- | --- | --- |
| `messages` | Ciphertext envelopes and routing metadata | Until `expiresAt` (disappearing timer), and **never more than 30 days** after `serverReceivedAt` (`MESSAGE_MAX_AGE_DAYS`), delivered or not. View-once rows are deleted on first read. | `RetentionService` (`expiredMessages`, `agedMessages`); `MessagesService` (view-once) |
| `attachments` + object storage | Encrypted blob, its size and sha256 | When a sweep deletes the last visible message that references it, blob and row are deleted as soon as that batch commits. Orphans — pending, failed, or uploaded but referenced by no message or only by delete-for-everyone tombstones (this covers view-once consumption and delete for everyone) — are deleted 24 hours after upload. All blobs of an account are deleted on account deletion. Download tickets are issued only for a live message in a conversation the requester belongs to. | `RetentionService` (message sweeps, `orphanAttachments`); `AccountService` |
| `message_receipts` | Per-recipient delivered/read timestamps | Read receipts: 7 days after `readAt`. Unread: 30 days after `deliveredAt`. Always deleted with their message. | `RetentionService` (`receipts`) |
| `reactions` | Reaction per message and user | Deleted with their message (cascade), so at most 30 days. | Message sweeps |
| `stories` | Text story and caption | 24 hours. | `RetentionService` (`expiredStories`) |
| `story_views` | Who viewed which story | Deleted with their story. | `RetentionService` (`expiredStories`) |
| `call_records` | Who called whom, when, how long | A call still ringing after 90 seconds becomes `missed`; a call still active after 12 hours becomes `ended`. Terminal calls are deleted after `VEIL_CALL_RECORD_RETENTION_DAYS` (default 30; 0 keeps them). | `RetentionService` (`missedCalls`, `endedCalls`, `callRecords`) |
| `abuse_reports` | Reporter, reported user, reason | 90 days. The free-text note is accepted from clients but never stored. | `RetentionService` (`abuseReports`); `SafetyService` |
| `one_time_prekeys` | Public X3DH one-time prekeys | Unconsumed: until claimed or the device is deleted. Consumed: `VEIL_PREKEY_CONSUMED_RETENTION_DAYS` (default 30; 0 keeps them) so a keyId is never reused mid-flight. | `RetentionService` (`consumedPrekeys`) |
| `secret_blobs` | One-time link ciphertext | Deleted on first read; unopened links are deleted at `expiresAt`. | `SecretService`; `RetentionService` (`secretBlobs`) |
| `device_transfer_sessions` | Transfer token hash, old device, expiry | Closed after the transfer TTL (default 300 s); rows are deleted with the account. Not swept yet. | `DeviceTransferService`; `AccountService` |
| `devices` | Public identity, prekey and auth keys, push token, last-seen times | Until revoked or the account is deleted. Coarsening `lastSeenAt`/`lastSyncAt` is a follow-up. | `AccountService` |
| `users`, `user_profiles`, `user_contacts`, `user_blocks`, `conversation_mutes` | Account, profile and social graph | Account lifetime. | `AccountService` |
| `conversations`, `conversation_members`, `device_conversation_states`, `group_metas`, `channel_metas`, `group_member_epochs` | Membership and sync cursors | Conversation or account lifetime. | `AccountService`, conversation deletion |
| `recovery_blobs` | Legacy recovery backup | Scheduled for removal: the recovery module is deleted in this wave and the table is dropped in the next. | — |

### Short-lived keys in the ephemeral store (Redis)

| Key | Kept for | Notes |
| --- | --- | --- |
| `budget:*` | 1 hour | Key-directory budgets. The key holds only a SHA-256 digest of who looked up whom. |
| `transfer:claim:*` | Transfer TTL | The first claim of a device-transfer session; see `device-transfer-flow.md`. |

## Directory privacy

The key directory follows the same minimisation:

- `GET /v1/keys/:handle` needs a signed-in device. One-time prekeys are claimed
  atomically in one transaction, at most 20 per hour per (requester device,
  target user) and 50 per hour per target device. Over budget, the lookup
  still succeeds but returns no one-time prekey and consumes nothing.
- The deprecated public `GET /v1/users/:handle/key-bundle` returns no display
  name, avatar, device platform or update time, answers with
  `Deprecation: true` and a `Link` to its successor, and allows 20 lookups per
  hour per (client, handle).
- `GET /v1/users/:handle` needs a signed-in device and returns only id, handle
  and status. `GET /v1/profile/:handle` and stories need a real relationship
  (mutual contacts, or a shared direct or group conversation for profiles) and
  no block in either direction; strangers get the same 404 as a missing handle.

## Relationship to other tracks

This is the present-day complement to the **sealed sender** spec: sealed
sender stops the server from learning the *sender* of a message; retention
stops it from *keeping* the metadata it does see.
