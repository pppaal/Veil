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

- NestJS modules by domain: `AuthModule`, `UsersModule`, `DevicesModule`, `ConversationsModule`, `MessagesModule`, `AttachmentsModule`, `RealtimeModule`, `DeviceTransferModule`, `GroupsModule`, `ContactsModule`, `ProfileModule`, `CallsModule`, `StoriesModule`, `ChannelsModule`
- Prisma schema for all core entities
- challenge/verify device auth instead of password auth
- rate limiting, DTO validation, structured logging without sensitive content
- WebSocket gateway for delivery/read/presence/sync events

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

## Crypto seam

The production system uses `LibCryptoAdapter` (X25519+AES-256-GCM). The important design constraint is the boundary:

- `CryptoEngine` owns message encryption/decryption
- attachment key wrapping is abstracted
- contracts preserve envelope semantics (`veil-envelope-v1`)
- the adapter can be upgraded without redesigning routes, storage, or UI flows
- external cryptographic audit is required before production claim
