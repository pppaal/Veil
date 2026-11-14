# Message Flow

## Direct message send

1. Sender fetches recipient public key bundle.
2. Sender encrypts locally through `CryptoEngine`.
3. The mobile client assigns a `clientMessageId` and stages the outbound item in the local pending queue.
4. For attachments, the mobile client first stages an opaque local temp blob, uploads it to object storage, finalizes the attachment record, and only then sends the encrypted envelope with the attachment reference.
5. Mobile sends only the envelope to `POST /v1/messages`.
6. API authorizes the sender through the conversation policy (see below), checks the envelope version against the conversation, and validates that `recipientUserId` matches the direct conversation peer.
7. API stores ciphertext, nonce, the envelope version, timestamps, and the outer attachment pointer (`attachmentId` only).
8. Realtime gateway emits `message.new` (with no receipt timestamps) to the recipients and `conversation.sync` to every member.
9. If the recipient has no active socket but does have a registered push token, the backend may send a metadata-only wake-up hint.
10. Recipient device retrieves the envelope and decrypts locally.

## Group message send

1. Sender encrypts locally: a group that opted into Sender Keys uses its per-sender chain (`veil-group-v1`); a legacy group uses its shared bundle with a pairwise envelope format.
2. The envelope omits `recipientUserId` (field is optional for groups).
3. Mobile sends the envelope to `POST /v1/messages`, with `groupEpoch` when the group uses Sender Keys.
4. API skips the direct-peer validation check for non-direct conversation types.
5. API fans out the message to all conversation members via realtime and push fallback.
6. Each member device retrieves the envelope and decrypts locally.

## Conversation policy

Every conversation-scoped endpoint and realtime handler authorizes through one declarative table (`apps/api/src/common/conversation-access/conversation-policy.ts`):

| Type    | Role         | send | edit | delete | react | typing | setTimer | call | readMembers | readHistory | markRead | manageMembers |
| ------- | ------------ | ---- | ---- | ------ | ----- | ------ | -------- | ---- | ----------- | ----------- | -------- | ------------- |
| direct  | member       | yes  | yes  | yes    | yes   | yes    | yes      | yes  | yes         | yes         | yes      | no            |
| group   | member       | yes  | yes  | yes    | yes   | yes    | yes      | no   | yes         | yes         | yes      | no            |
| group   | admin, owner | yes  | yes  | yes    | yes   | yes    | yes      | no   | yes         | yes         | yes      | yes           |
| channel | subscriber   | no   | no   | no     | no    | no     | no       | no   | no          | yes         | yes      | no            |
| channel | admin, owner | yes  | yes  | yes    | no    | no     | yes      | no   | yes         | yes         | yes      | yes           |

- Any other type/role pair may do nothing.
- A non-member gets `403 conversation_membership_required`, whether or not the conversation exists. A member whose role lacks the action gets `403 conversation_role_required`.
- In a direct conversation, a block in either direction makes the peer unreachable for send, edit, react, typing and call (`403 peer_unreachable`). Reading history, deleting your own message and changing the timer still work, and the delivered/read receipts they produce reach only the reader's own devices.
- Calls are direct-only; placing one elsewhere is `403 call_not_allowed`.
- Group members only see messages received after they joined: history, the conversation-list `lastMessage`, delivered receipts and message-level actions all hide the backlog. Realtime events about an existing message (`message.edited`, `message.deleted`, `message.reaction`, `message.consumed`) reach only the members who joined no later than its `serverReceivedAt`; an edit is re-encrypted under the current group key, which a late joiner already holds. Channels are a public broadcast and keep their backlog visible to new subscribers.
- Channel subscribers never see each other: conversation summaries list only the owner, admins and the viewer, and `GET /conversations/channel/:id` gives non-staff only the subscriber count and the admins.
- Groups are capped at 25 members (`409 group_member_limit`). Sender Keys cannot be turned off once enabled (`400 sender_keys_irreversible`). The owner must transfer ownership (`POST /conversations/group/:id/owner`) before leaving (`409 owner_immutable`).

## Envelope versions

- The relay persists `envelope.version` and returns it as `version` on every message summary, including realtime `message.new` and `message.edited`, so receivers pick the right decryptor.
- Direct conversations, channels and legacy groups accept the pairwise family: `veil-envelope-v1`, `veil-envelope-v1-dev`, `veil-envelope-v2`, `libsignal-v1`. A group with Sender Keys accepts only `veil-group-v1`, so no member can downgrade it. Anything else is `400 envelope_version_mismatch`.
- A production relay refuses the development markers `veil-envelope-v1-dev` and the `dev-wrap` attachment hint (`400 envelope_version_forbidden`).
- An edit must keep the stored version (`400 envelope_version_mismatch`), comes from the original sending device, and is only possible within 24 hours of `serverReceivedAt` (`403 edit_window_expired`).
- Messages stored before migration `0017_conversation_integrity` were written without a version, so they all report `veil-envelope-v1`, including Sender Keys (`veil-group-v1`) and `libsignal-v1` history. The true version cannot be recovered. A client that fails to decrypt such a message should retry with the decryptor the conversation currently uses, and an edit of such a message is refused unless it really was `veil-envelope-v1`.

## Ordering

- `conversationOrder` is allocated from `conversations.last_order`, incremented under the row lock in a default-isolation transaction. Orders are unique per conversation and never reused, even after the newest message is hard-deleted by view-once consumption or expiry.
- During a rolling deploy of migration `0017_conversation_integrity`, instances still on the old `MAX(conversation_order) + 1` allocator insert without bumping `last_order`. A send that then collides on `(conversation_id, conversation_order)` raises `last_order` to the highest stored order and retries once, so the counter catches up instead of failing every later send. A send can still fail while old instances keep writing to the same conversation; the client's idempotent retry succeeds once they are gone.
- A retried send with the same `(senderDeviceId, clientMessageId)` returns the stored message with `idempotent: true`.

## Client delivery lifecycle

- `uploading`
  - Attachment blobs are being uploaded and verified before the message envelope is sent.
- `pending`
  - The outbound envelope is queued locally and eligible for automatic retry.
- `sent`
  - The relay accepted the envelope and assigned `conversationOrder`.
- `delivered`
  - The recipient device fetched the envelope or the relay reconciled delivery metadata.
- `read`
  - The recipient marked the message as read.
- `failed`
  - The relay refused the send with a permanent error, or (mobile) answered with a retryable error on 5 attempts in a row. A send that got no response at all does not become `failed` on its own.
- Sender-side message bubbles should keep the body readable and surface delivery state as a short explicit badge, not a verbose sentence.

## Retry and reconnect behavior

- Outbound items are keyed by `clientMessageId` for idempotent re-send.
- A send that got no response (the device is offline or the request timed out) stays queued and keeps retrying with exponential backoff capped at 30 seconds, for as long as that lasts. The sealed envelope stays valid and the relay deduplicates by `clientMessageId`, so no attempt limit applies.
- The 5-attempt limit (mobile) applies only to failures the relay answered: a 5xx, 408, 409 or 429, or an attachment upload dropped mid-stream. After the fifth the message is `failed` and waits for a manual retry. A permanent relay error (for example `group_epoch_stale` or `conversation_membership_required`) fails it at once.
- The web client retries with the same capped backoff until the relay accepts the envelope or refuses it with a 4xx other than 429.
- Reconnect forces an immediate outbox drain and a batched first-page backfill for active, cached, or recently hinted conversations.
- App resume forces a realtime refresh so stale sockets do not linger after background wake-up.
- Late `message.delivered` and `message.read` events are buffered locally until the corresponding message page is present.
- Out-of-order receipt events must only move state forward. A late `delivered` event must not regress a message that is already `read`.
- Long conversations paginate by `conversationOrder`, newest first on the wire and oldest first in the local UI.
- If local search is active inside a chat, the UI should explicitly say that results come from cached device-local text and that clearing search returns the user to full conversation context.

## Local search and history navigation

- Conversation search is local and limited to handle and display-name metadata already present on the device.
- Message search is local to the device-side cached conversation archive and only indexes content after local decryption.
- Search queries are never sent to the backend.
- The current private-beta build still does not provide a true encrypted full-text index for the entire archive; search is backed by the local cache for messages already materialized on this device.

## Attachment lifecycle

- Attachment sends move through three device-visible phases:
  - ticket request
  - opaque blob upload
  - encrypted envelope send
- The mobile UI tracks attachment transfer state through explicit phases:
  - `staged`: local temp blob prepared, upload not started
  - `preparing`: ticket requested, upload about to begin
  - `uploading`: opaque blob transfer in progress with progress tracking
  - `completing`: upload finished, finalizing attachment record
  - `failed`: upload or finalization failed, retry available
  - `canceled`: user explicitly canceled the upload
- Failed attachment uploads remain in the local queue and can be retried without changing the ciphertext-only relay model.
- Attachment retries reuse the device-local opaque temp blob and renew the ticket when necessary.
- Explicit cancel leaves the staged attachment in a failed local state so the user can retry without regenerating plaintext input.
- Attachment download resolution is a separate device-local state and should surface a transient `resolving ticket` state without exposing plaintext previews to the backend.
- Download resolution still uses a scoped download ticket and must not expose plaintext previews to the backend.

## Receipt consistency

- Receipt events (`message.delivered`, `message.read`) go only to the message sender's devices and the reader's own devices; other group members never learn who read what. Channels have no receipts at all, and in a direct conversation blocked in either direction the sender gets none.
- Every message summary carries only the requesting viewer's own receipt timestamps. Realtime broadcasts carry none. A sender learns about delivery and reads from the receipt events, not from history.
- Receipt transitions must only move forward: `sent -> delivered -> read`.
- Repeated `read` actions should not emit duplicate downstream receipt events after the first successful transition.
- Repeated or late realtime receipt events should merge timestamps with `max(existing, incoming)` semantics.
- Sender-side views derive receipt state from the receipt events they received, while recipient-side views derive it from their own receipt.

## Transient failure UX

- While the relay is disconnected, queued or failed sends stay visible in the conversation with explicit local state.
- The conversation view should communicate whether the relay is reconnecting and when the next retry window opens.
- Attachment uploads remain attached to the same local outbound item across retry and cancel transitions.

## Server-visible fields

- `ciphertext`
- `nonce`
- `version` (envelope format)
- `messageType`
- `attachmentId` (the outer attachment pointer; content type, size, digest and key material live only in the encrypted inner payload, and legacy metadata sent by older clients is discarded)
- `expiresAt`
- `serverReceivedAt`
- `clientMessageId`
- `conversationOrder`
- delivery and read receipt timestamps

## Forbidden server behavior

- decrypting messages
- logging message bodies
- putting plaintext message content into push payloads
- adding admin viewers for content inspection

## Push fallback

Push is a secondary wake-up path, not a content channel. Payloads must remain metadata-only and may contain fields such as:

- `kind`
- `messageId`
- `conversationId`
- `serverReceivedAt`

Push must never contain plaintext message bodies, filenames, attachment keys, decrypted previews, or local queue metadata.

## Disappearing messages

The server stores an outer `expiresAt` as metadata. It is not authenticated: protocol v2 keeps the authenticated expiry inside the encrypted payload, and clients expire a message at the earlier of the inner and outer values. The relay may therefore set or clamp the outer value:

- A value more than 60 seconds in the past or more than 30 days ahead is rejected (`400 validation_failed`).
- In a conversation with a disappearing timer, a missing value becomes `now + timer`, and a value beyond `now + timer + 300 s` is clamped to `now + timer`.

Expired messages are hidden from every read path immediately; the retention service deletes them in the background. Local clients are responsible for expiration UX and cache cleanup. The backend should not become the canonical plaintext lifecycle manager.
