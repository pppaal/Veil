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

- `CryptoEngine` abstraction with a mock adapter
- secure device secret references via `flutter_secure_storage`
- local app lock hooks via `local_auth`
- local cache definitions via Drift/SQLite
- feature-oriented screen scaffolds for onboarding, chat, transfer, and settings

## API architecture

- NestJS modules by domain: `AuthModule`, `UsersModule`, `DevicesModule`, `ConversationsModule`, `MessagesModule`, `AttachmentsModule`, `RealtimeModule`, `DeviceTransferModule`
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

## Crypto seam

The current system intentionally uses a mock adapter. The important design constraint is not the mock itself, but the boundary:

- `CryptoEngine` owns message encryption/decryption
- attachment key wrapping is abstracted
- contracts preserve envelope semantics
- future audited crypto can replace the adapter without redesigning routes, storage, or UI flows
