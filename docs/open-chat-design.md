# VEIL Open Chat — Design Note

Status: draft, not yet implemented.
Owner: TBD.
Last updated: 2026-04-22.

This document describes the design for VEIL's "open chat" feature — a
pseudonymous group-conversation mode in which a participant's stable handle
is never exposed to other members of the room. It intentionally does not
describe monetization, moderation, or discoverability-at-scale, which are
follow-up concerns that should be decided only after the privacy model is
locked down.

## Why this exists

KakaoTalk's OpenChat is the closest product analogue in the Korean market.
Its design ties every participant back to a real phone number, which means
an open chat on Kakao is an identity-leak waiting to happen: a moderator or
sufficiently-motivated co-participant can correlate your open-chat
nickname with your real account.

VEIL's identity model is already phone-number-free and handle-based, but
the handle is global: if you join a public-ish room today with your
regular handle, you are instantly doxxable to strangers. The point of this
feature is to let participants join "open" rooms without exposing any
identifier that links back to their outside-the-room existence.

This is the first Veil-shaped feature Kakao cannot match at the protocol
level — not because Kakao could not add nicknames, but because its
handle-to-phone binding makes the underlying linkage unavoidable. We should
ship this as Veil's signature differentiation.

## Goals

1. A participant's stable handle is never visible to other participants of
   an open chat, full stop. Not in the member list. Not in message metadata.
   Not in attachment uploads. Not in push notifications.
2. Joining an open chat requires no contact exchange — an invite token (URL
   or QR) is sufficient.
3. A participant can leave an open chat and their prior presence in that
   room becomes unlinkable from their other activity on Veil.
4. The crypto guarantees of normal conversations (forward secrecy,
   post-compromise security, server ciphertext-only) hold in open chats.
5. No feature of open chat may weaken the existing threat model for
   closed-chat participants.

## Non-goals

- Server-side search or directory of open chats. Discovery is out-of-band
  (links shared in other apps, QR posters, etc.) for the MVP.
- Moderation tooling. The MVP has a single owner/admin role with basic
  kick/ban, nothing more.
- Handle-less "walk-in" participants (no Veil account). Deferred to Phase 2.
- Cross-device sync of open-chat alias state. The MVP treats each device's
  alias as device-local.

## Two phases

**Phase 1 — aliased handles (MVP).** Participants have a stable Veil account
(handle + device) but present a per-conversation alias when inside an open
chat. The handle is never transmitted to other participants. Phase 1
requires modest schema changes and no new crypto primitives.

**Phase 2 — handle-less guests (deferred).** Someone with no Veil account
scans an invite, the app provisions an ephemeral device + alias bound only
to that one conversation, and they can participate until they discard the
device. Phase 2 requires making `Device.userId` nullable and guarding every
query path that currently assumes it — a significantly larger lift.

Everything below describes Phase 1 unless explicitly tagged `(Phase 2)`.

## Data model changes

Three new concepts; everything else reuses the existing schema.

### `ConversationParticipantAlias`

```
id                   String   @id @default(cuid())
conversationId       String
userId               String           // Phase 1 requires userId; Phase 2 makes nullable
deviceId             String           // the participating device
alias                String           // display name inside this conversation
aliasColor           String?          // optional UI affordance
createdAt            DateTime @default(now())
expiresAt            DateTime?        // null = persistent while in the room
revokedAt            DateTime?

@@unique([conversationId, userId])    // one alias per user per room
@@unique([conversationId, alias])     // aliases must be unique within a room
@@index([conversationId])
```

Rationale for `@@unique([conversationId, alias])`: collisions would force
receivers to disambiguate which `Anonymous Fox` sent a message, which is a
UX and auditability footgun. The server rejects duplicate aliases at
join-time; the client picks another.

### `Conversation.kind`

Add a discriminator field (or extend the existing `type` enum) with a new
value `open`. `open` conversations behave like groups for message routing
but use aliases for addressing and hide membership lists by default.

### `OpenChatInvite`

```
id              String   @id @default(cuid())
conversationId  String
token           String   @unique       // the shareable secret
createdByUserId String
createdAt       DateTime @default(now())
expiresAt       DateTime?
maxUses         Int?
usesConsumed    Int      @default(0)
revokedAt       DateTime?
@@index([conversationId])
```

Tokens are high-entropy (≥128 bits) and are the sole bearer of join
authorization. Tokens can be time-bounded, use-bounded, or both.

## API surface

### `POST /v1/conversations/open`

Body: `{ title: string, aliasForCreator: string }`

Creates an open conversation and a `ConversationParticipantAlias` for the
creator. Returns the conversation id and a freshly minted invite token.

### `POST /v1/conversations/open/:conversationId/invites`

Body: `{ expiresAt?, maxUses? }` — owner/admin only.

Rotates or creates a new invite token. Previous tokens remain valid unless
explicitly revoked, so an owner can vend time-limited per-audience tokens
without disrupting existing members.

### `POST /v1/open/join`

Body: `{ token: string, alias: string, aliasColor?: string }`

The sole join endpoint. Server validates the token, enforces alias
uniqueness inside the room, creates the `ConversationParticipantAlias`,
and creates the normal `ConversationMember` record wired to the caller's
user. Response returns the conversation id and the caller's alias record;
it never returns the handles of other members.

### Member-list queries

Open conversations expose only alias records, never `User.handle`. The
existing conversation-members endpoint must branch on `Conversation.kind`:
for `open`, return `ConversationParticipantAlias[]`; for `direct`/`group`,
return the current shape.

### Message send

Unchanged on the wire. The sender's userId is resolved to an alias
server-side before the message is emitted to other participants; receivers
see only the alias. The crypto envelope remains identical (senderDeviceId
is still present in clear, see "Threat model" below for handling).

## Crypto implications

The v2 Double Ratchet already operates at the device-pair level. For group
and open conversations, each peer-pair runs its own ratchet, so the
per-pair forward secrecy and post-compromise security properties transfer
unchanged. Adding aliases does not touch the ratchet.

What does change:

- The key bundle directory currently exposes `{userId, deviceId, handle,
  identityPublicKey, signedPrekeyBundle}`. For open chats, the server
  must serve a **handle-redacted variant** of the bundle — `{aliasId,
  deviceId, identityPublicKey, signedPrekeyBundle}` — so joining clients
  can bootstrap sessions with other members without learning their
  handles.
- The envelope codec does not need changes: the envelope carries
  `senderDeviceId`, not `senderHandle`. The mobile client must render
  `senderDeviceId` through the alias map instead of through the contact
  list.

## Privacy properties

| Property                                    | Phase 1 | Phase 2 |
| ------------------------------------------- | :-----: | :-----: |
| Handle never sent to other participants     |   Yes   |   Yes   |
| Handle never sent to the server in the join |   No    |   Yes   |
| Per-room alias                              |   Yes   |   Yes   |
| Exit leaves no linkable state on device     | Partial |   Yes   |
| Server cannot correlate aliases across rooms for the same user | No   |   Yes   |
| Server cannot correlate aliases across rooms for the same device | No | No (same device = same pair of crypto keys) |

Phase 1 deliberately lets the *server* see the handle→alias mapping — the
server still authenticates the JWT, which is handle-bound. This is a known,
accepted weakness for the MVP. The threat Phase 1 closes is
*participant*-side doxxing, which is the more common real-world incident.
Phase 2 closes the server-side mapping by letting a guest device exist
with no linked user.

"Server cannot correlate aliases across rooms for the same device" is
false in both phases because the ratchet identity keys (Ed25519 + X25519)
are device-level — joining two rooms with the same device necessarily
reuses those keys. If we want this property we must rotate identity keys
per room, which is a much larger change deferred out of scope.

## Threat model notes

- **Sender-device linkability.** `CryptoEnvelope.senderDeviceId` on the
  wire is plaintext. A malicious server can observe that the same deviceId
  is sending in two rooms. This is out of scope for Phase 1; tracking
  mitigations require either per-conversation device pseudonyms or
  onion-routed relaying.
- **Attachment bucket metadata.** Attachment storage keys
  (`attachments/:deviceId/:attachmentId`) embed deviceId. Either re-path
  to conversation-scoped storage keys for open chats, or accept the
  linkability for the MVP and flag it as a known issue.
- **Push notifications.** Push metadata must never expose the room title,
  sender alias, or handle. Open chats should default `pushDeliveryEnabled`
  to false or to a strictly-content-free hint.
- **Read-receipts and typing indicators.** Receipts currently fan out per
  `userId`. For open chats, fan out per alias to avoid exposing handle on
  the receipt emit path.
- **Account transfer.** Device transfer currently moves a handle between
  devices. Aliases on the *source* device must either migrate (losing
  the uniqueness guarantee if the alias was already claimed on the target)
  or be revoked at transfer time. MVP: revoke at transfer; re-join with a
  fresh alias on the new device.

## UX flow sketch (Phase 1)

1. **Create.** Creator taps "Start open chat", picks a title and their own
   alias. App calls `/open` and shows the invite token with a share sheet.
2. **Invite.** Creator shares the invite URL out-of-band (any other app,
   QR code, etc.). The URL encodes only the token; opening it on another
   Veil device surfaces a "Join as…" prompt that forces an alias choice.
3. **Join.** Joiner enters an alias (client enforces length, rejects
   lookalikes of the creator's alias client-side as a courtesy; server
   enforces uniqueness authoritatively). App calls `/open/join`.
4. **In-room.** Member list renders aliases only. Tap-and-hold on a member
   opens an alias-scoped menu (report, mute, block-in-this-room) — never
   a "view profile" action.
5. **Leave.** "Leave room" revokes the alias record server-side and wipes
   the alias + ratchet state for this conversation from the device. Coming
   back later requires a new alias.

## Out-of-scope decisions parked here on purpose

- How to prevent a spammy creator from spawning thousands of open chats.
  Answer: rate-limit conversation creation at the API; revisit when abuse
  emerges.
- How to render "someone typing…" without emitting aliases for every
  keystroke. Answer: batch typing events per room, per alias, with a 500ms
  minimum interval.
- How to support sticker/emoji reactions without revealing the reactor's
  alias to the entire room. Answer: reactions render with alias; this is
  intentional — if you don't want to attach your alias to a message, don't
  react.
- Compliance / legal surfaces around open chats. Deferred until product
  direction is firmer.

## Next actions if this document is accepted

1. Land the schema migration for `ConversationParticipantAlias`,
   `Conversation.kind`, and `OpenChatInvite` behind a `VEIL_OPEN_CHAT` env
   flag default-off.
2. Implement the three API endpoints above with the alias uniqueness and
   token-authorized join logic.
3. Add member-list branching so handle fields are stripped for open
   conversations at the response layer, not at the persistence layer.
4. Ship a minimal Flutter screen set: create, invite-share, join,
   in-room. Reuse the existing chat UI; override avatar + name rendering
   to alias-aware builders.
5. Revisit Phase 2 after Phase 1 has run in private beta long enough to
   validate the alias model.
