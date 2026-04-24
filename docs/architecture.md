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

## Mobile backup primitive

- `BackupEnvelope` seals a plaintext payload under a user passphrase. PBKDF2-SHA256 (600k iterations, OWASP 2023 floor) derives a 256-bit key that feeds AES-256-GCM with fresh salt/nonce per seal. Pure-dart so every Flutter target works without a native Argon2 dependency; version marker preserved so a future revision can upgrade to Argon2id without a format bump.

## Crypto seam

The production system uses `LibCryptoAdapter` (X25519+AES-256-GCM). The important design constraint is the boundary:

- `CryptoEngine` owns message encryption/decryption
- attachment key wrapping is abstracted
- contracts preserve envelope semantics (`veil-envelope-v1`)
- the adapter can be upgraded without redesigning routes, storage, or UI flows
- external cryptographic audit is required before production claim
