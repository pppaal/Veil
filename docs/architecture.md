# VEIL Architecture Overview

## Core stance

VEIL is device-centric. Private key material lives on the device. The backend acts as:

- a handle directory
- a public key bundle directory
- an encrypted envelope relay
- an encrypted attachment metadata store
- a device transfer coordinator

The backend must never become a plaintext message processor.

## Monorepo layout

- `apps/mobile`: Flutter application
- `apps/api`: NestJS API and WebSocket gateway
- `packages/shared`: crypto/domain abstractions and safe utility code
- `packages/contracts`: typed API contracts
- `infra/docker`: local infra
- `docs`: design and security documentation

## Mobile architecture

- `CryptoEngine` abstraction with a production adapter (`LibCryptoAdapter`: X25519+AES-256-GCM+Ed25519)
- secure device secret references via `flutter_secure_storage`
- local app lock hooks via `local_auth`
- local cache definitions via Drift/SQLite
- feature-oriented screens: onboarding, chat, contacts, transfer, settings, reactions, and profile

### Layers (`apps/mobile/lib/src`)

- `core/`: platform, crypto, network, storage and the shared domain models (`core/domain`: conversations, messages, search). Core imports nothing from `features/` or `app/`; `scripts/crypto-architecture-check.mjs` enforces it. The old `core/router` paths remain only as re-exports of `app/router`.
- `core/di/core_providers.dart`: providers for storage, crypto (bootstrapped through the adapter registry), realtime, notifications and app lock.
- `features/`: one directory per feature, each with its own data providers (messenger, device transfer, attachments, privacy preferences).
- `app/`: composition: the session controller and its providers (`app/session`), the router (`app/router`) and the theme provider. `app/app_state.dart` is a re-export barrel and declares nothing.

### Messenger

`VeilMessengerController` is a facade of at most 400 lines with the public API the screens use. It delegates to the services under `features/conversations/data/messenger/` (each at most 450 lines), which `MessengerServices` wires together:

- `MessengerStateStore` holds conversations, loaded messages and paging, and asks for one listener notification per microtask however many changes a step makes.
- `MessengerPersistence` writes that state to the encrypted cache through one serialized queue: changes only mark what changed, and a flush 100 ms after the last change (at most 1 s), on app pause or on dispose writes the rows that differ from what it last wrote. Outbox records are queued at once, without waiting for a flush, and land behind any write already in the queue. Only rows that reached a database count as written: a failed write, or one that found no database (an iOS launch before first unlock), leaves its conversations to the next flush, which writes them whole. A wipe (sign-out, device wipe, revocation) drops everything the writer still holds, and it writes nothing more until the next identity starts it over (a sign-out does not); `CacheHandle` makes the wipe wait for any write already under way. Relay results that arrive after the identity they were fetched for signed out or changed (a conversation list or history page still on its way) are dropped: `MessengerSessionContext.generation` changes with the identity, so they reach neither the next identity's state nor its cache. Local notices are written at once, not on the debounced flush, because the event behind one is not raised again after a restart. The cache is read back at start in one joined query.
- `ConversationCryptoRouter` and `PeerSessionResolver` route every encrypt and decrypt (Sender Keys groups through the group engine, everything else pairwise under the identity pins); `IdentityChangeService` handles approving and declining identity changes.
- `OutboxService`, `AttachmentTransferService`, `ConversationSyncService`, `RealtimeEventRouter` (typed dispatch over `RealtimeEvent.tryParse`), `ReceiptService`, `ReactionService` and `MessageSearchService` each own one concern. The typed dispatch drops an event that lacks a field the API always sends (`typing.stop` without `userId` and `handle`, `conversation.sync` with an unknown `reason`, `presence.update` without `updatedAt`, `group.epoch.bumped` without `reason` and `userId`); only receipts accept a missing `userId`. This is a deliberate tightening over the untyped handlers it replaced and matches what `apps/api` emits.
- `MessageContentService` holds every message's plaintext: each inbound frame is decrypted once, and its opened content is stored before the engine commits the ratchet step that spends the key (a `BeforeCommit` hook threaded through the router, the pairwise cipher and the Sender Keys engine). A decrypt whose content or state could not be stored commits nothing and is retried on the next read. Opened content is bound to the conversation and sender device it was opened under (or written by, for this device's own text); a message the relay later lists under another sender or conversation reads as failed, and nothing is decrypted again or replaced. Merges keep the sender and conversation a message id was first seen with, a history page keeps only frames sealed for that conversation, and an ack must echo the message just sent. A pairwise frame under this device's own id is never opened. A frame refused only because it is more than 200 keys ahead waits (non-final) and is retried after each history page; a refresh pages up to 2000 messages back.
- `ConversationSyncService` announces every member the relay's list adds to or removes from a group (`group.member_added`, `group.member_removed` notices), against the member set this device last showed, which is kept in the keystore beside the 1:1 peer bindings; a group's first listing only records it.
- `RealtimeEventRouter` reconnects by itself after the relay closes the socket (it does so when the access token expires, and socket.io does not reconnect after a server disconnect): it asks the shared token-refresh gate for a fresh token and reconnects with backoff from 1 s to 60 s, and stops when the session cannot be refreshed.
- `OutboxService` keeps retrying, with backoff up to 30 s, a send that got no response at all (offline, timed out); the five-attempt budget applies to failures the relay answered. Disappearing-message expiries are stamped, and checked, on the relay's clock as the `Date` header reports it, corrected by at most an hour (`ServerClock.boundedNow`).
- `PresenceTypingService` is a notifier of its own with a clear timer per conversation, so typing in one chat does not rebuild another.
- `DisappearingMessagesService` arms one one-shot timer for the next expiry; nothing ticks while nothing is due. That timer runs on the monotonic clock, which stops while the device sleeps, so the messenger also reconciles expiry when the app resumes.

## API architecture

- NestJS modules by domain: `AuthModule`, `UsersModule`, `DevicesModule`, `ConversationsModule`, `MessagesModule`, `AttachmentsModule`, `RealtimeModule`, `DeviceTransferModule`, `GroupsModule`, `ContactsModule`, `ProfileModule`, `CallsModule`, `StoriesModule`, `ChannelsModule`, `SafetyModule`
- Prisma schema for all core entities
- challenge/verify device auth instead of password auth
- rate limiting (global 60/min + per-route tightening on auth, message send, attachment tickets, abuse reports), DTO validation, structured logging with PII redaction, request-ID propagation
- WebSocket gateway for delivery/read/presence/sync events
- periodic cron (10 min) that hard-deletes globally expired messages so idle conversations don't retain past-TTL rows

## Data boundary

The server handles:

- ciphertext-like blobs
- nonces
- opaque attachment metadata
- receipts
- timestamps
- public key bundles

The server must not handle:

- plaintext message bodies
- attachment plaintext
- device private keys
- admin decryption utilities

## Conversation types

- `direct`: one-to-one with strict recipient validation
- `group`: multi-member with server fan-out, optional `recipientUserId`
- `channel`: broadcast (planned)

## Privacy-aligned message features

- **Disappearing messages**: per-conversation default TTL (seconds) stored on `Conversation.disappearingTimerSeconds`. Client stamps `expiresAt` on each outgoing message; server enforces as an upper bound and lazily prunes on read. A global cron sweeps idle conversations every 10 minutes. `conversation.timer.changed` fans out to every member so multi-device stays in sync.
- **View-once messages**: `Message.viewOnce` flag. When any non-sender member marks read, server hard-deletes the row and broadcasts `message.consumed` so every member drops the ciphertext from local cache.
- **User blocks**: bidirectional check on `createDirect` (returns `NotFound` — opaque to blocked user) and on `sendMessage` (returns `peer_unreachable`). Block state applies to direct conversations; groups expect block-by-removal.
- **Conversation mutes**: `ConversationMute` row suppresses push wake while leaving realtime + persistence untouched, so other devices stay in sync. Optional `mutedUntil` auto-unmutes.
- **Abuse reports**: reporter files to `AbuseReport` table with a tight throttle (6/min) so the moderation queue can't be weaponized as a DoS against a target.

## No backup

The app has no backup and no recovery path: message history lives only on the device that received it, and a lost device is unrecoverable by design (see `docs/no-recovery.md`). `scripts/crypto-architecture-check.mjs` fails if a `core/backup` module appears.

## Crypto seam

The production system uses `LibCryptoAdapter` (X25519+AES-256-GCM). The important design constraint is the boundary:

- `CryptoEngine` owns message encryption/decryption
- attachment key wrapping is abstracted
- contracts preserve envelope semantics (`veil-envelope-v1`)
- the adapter can be upgraded without redesigning routes, storage, or UI flows
- external cryptographic audit is required before production claim
