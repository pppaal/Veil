# Message Flow

## Direct message send

1. Sender fetches recipient public key bundle.
2. Sender encrypts locally through `CryptoEngine`.
3. The mobile client assigns a `clientMessageId` and stages the outbound item in the local pending queue.
4. For attachments, the mobile client first stages an opaque local temp blob, uploads it to object storage, finalizes the attachment record, and only then sends the encrypted envelope with the attachment reference.
5. Mobile sends only the envelope to `POST /v1/messages`.
6. API validates that `recipientUserId` matches the direct conversation peer.
7. API stores ciphertext, nonce, metadata, timestamps, and optional attachment reference.
8. Realtime gateway emits `message.new` and `conversation.sync`.
9. If the recipient has no active socket but does have a registered push token, the backend may send a metadata-only wake-up hint.
10. Recipient device retrieves the envelope and decrypts locally.

## Group message send

1. Sender encrypts locally using the group conversation's shared bundle (no per-peer key fetch).
2. The envelope omits `recipientUserId` (field is optional for groups).
3. Mobile sends the envelope to `POST /v1/messages`.
4. API skips the direct-peer validation check for non-direct conversation types.
5. API fans out the message to all conversation members via realtime and push fallback.
6. Each member device retrieves the envelope and decrypts locally.

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
  - Automatic retry budget was exhausted or the relay rejected the send with a permanent error.
- Sender-side message bubbles should keep the body readable and surface delivery state as a short explicit badge, not a verbose sentence.

## Retry and reconnect behavior

- Outbound items are keyed by `clientMessageId` for idempotent re-send.
- Temporary relay or network failures stay in the local queue and retry with bounded backoff.
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

- Receipt transitions must only move forward: `sent -> delivered -> read`.
- Repeated `read` actions should not emit duplicate downstream receipt events after the first successful transition.
- Repeated or late realtime receipt events should merge timestamps with `max(existing, incoming)` semantics.
- Sender-side views derive receipt state from the recipient receipt record, while recipient-side views derive it from the local viewer receipt.

## Transient failure UX

- While the relay is disconnected, queued or failed sends stay visible in the conversation with explicit local state.
- The conversation view should communicate whether the relay is reconnecting and when the next retry window opens.
- Attachment uploads remain attached to the same local outbound item across retry and cancel transitions.

## Server-visible fields

- `ciphertext`
- `nonce`
- `messageType`
- `attachmentId`
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

The server stores `expiresAt` as metadata. Local clients are responsible for expiration UX and cache cleanup. The backend should not become the canonical plaintext lifecycle manager.
