# Message Flow

## Direct message send

1. Sender fetches recipient public key bundle.
2. Sender encrypts locally through `CryptoEngine`.
3. Mobile sends only the envelope to `POST /v1/messages`.
4. API stores ciphertext, nonce, metadata, timestamps, and optional attachment reference.
5. Realtime gateway emits `message.new` and `conversation.sync`.
6. Recipient device retrieves the envelope and decrypts locally.

## Server-visible fields

- `ciphertext`
- `nonce`
- `messageType`
- `attachmentId`
- `expiresAt`
- `serverReceivedAt`

## Forbidden server behavior

- decrypting messages
- logging message bodies
- adding admin viewers for content inspection

## Disappearing messages

The server stores `expiresAt` as metadata. Local clients are responsible for expiration UX and cache cleanup. The backend should not become the canonical plaintext lifecycle manager.
