# Message Flow

## Direct message send

1. Sender fetches recipient public key bundle.
2. Sender encrypts locally through `CryptoEngine`.
3. The mobile client assigns a `clientMessageId` and stages the outbound item in the local pending queue.
4. For attachments, the mobile client first uploads an opaque blob and only then sends the encrypted envelope with the attachment reference.
5. Mobile sends only the envelope to `POST /v1/messages`.
6. API stores ciphertext, nonce, metadata, timestamps, and optional attachment reference.
7. Realtime gateway emits `message.new` and `conversation.sync`.
8. If the recipient has no active socket but does have a registered push token, the backend may send a metadata-only wake-up hint.
9. Recipient device retrieves the envelope and decrypts locally.

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

## Retry and reconnect behavior

- Outbound items are keyed by `clientMessageId` for idempotent re-send.
- Temporary relay or network failures stay in the local queue and retry with bounded backoff.
- Reconnect forces an immediate outbox drain and a first-page backfill for active or cached conversations.
- Late `message.delivered` and `message.read` events are buffered locally until the corresponding message page is present.
- Long conversations paginate by `conversationOrder`, newest first on the wire and oldest first in the local UI.

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
- `senderDeviceId`
- `serverReceivedAt`

Push must never contain plaintext message bodies, filenames, attachment keys, decrypted previews, or local queue metadata.

## Disappearing messages

The server stores `expiresAt` as metadata. Local clients are responsible for expiration UX and cache cleanup. The backend should not become the canonical plaintext lifecycle manager.
