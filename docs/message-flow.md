# Message Flow

## Direct message send

1. Sender fetches recipient public key bundle.
2. Sender encrypts locally through `CryptoEngine`.
3. Mobile sends only the envelope to `POST /v1/messages`.
4. API stores ciphertext, nonce, metadata, timestamps, and optional attachment reference.
5. Realtime gateway emits `message.new` and `conversation.sync`.
6. If the recipient has no active socket but does have a registered push token, the backend may send a metadata-only wake-up hint.
7. Recipient device retrieves the envelope and decrypts locally.

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

Push must never contain plaintext message bodies, filenames, attachment keys, or decrypted previews.

## Disappearing messages

The server stores `expiresAt` as metadata. Local clients are responsible for expiration UX and cache cleanup. The backend should not become the canonical plaintext lifecycle manager.
