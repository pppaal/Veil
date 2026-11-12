# Web client architecture

The web client (`apps/web-demo`) is vanilla ES modules with no build step:
`index.html` loads `app.js`, which imports everything else. This page maps
the modules, the rules between them, and how a message travels through
them. `scripts/web-architecture-check.mjs` (`pnpm web:architecture:check`,
part of `pnpm ci:api`) enforces the rules marked **gate** below.

## Layers

```
app.js                 bootstrap: builds the store, services and views, wires them, signs in
src/ui/                the page: DOM helpers, dialogs, toasts, sounds
src/ui/views/          one module per screen part, each a factory taking its dependencies
src/app/               the state store, the messaging stack, and the services
src/features/          protocol features over crypto and platform (secure messaging, sender, transfer)
src/domain/            pure logic: message views, history, content, conversations, text rules
src/crypto/            protocol v2 (X3DH, Double Ratchet, pins, safety numbers), vector-checked
src/platform/          IndexedDB, the REST client, the session record, the content store, wipe
src/core/              base64url, expiry arithmetic
lib/, i18n/            formatting, the KakaoTalk parser, translations
```

Rules:

- **gate** `src/core`, `src/crypto`, `src/domain` and `src/platform` import
  nothing from `src/features`, `src/ui` or `src/app`; `src/features`
  nothing from `src/ui` or `src/app`; `src/app/services` nothing from
  `src/ui`. Services report to the user through callbacks the bootstrap
  hands them (`toast`, `onStatus`, `onSent`, `ui.showAuth`) and do not
  build or change page elements. Two of them do use page-level browser
  APIs directly: `notifications.js` (document title, visibility, the
  Notification API and window focus) and `history-sync.js` (skips
  background work while `document.hidden`).
- **gate** The lower four layers never touch the page: no `document`,
  `window`, `navigator`, `location`, observers or animation frames. Only
  `src/platform` may use `indexedDB`, `navigator.locks` and the Web
  Storage handles it is given; `globalThis` is read for `crypto` alone.
  Those layers therefore run unchanged under Node, which is how
  `__tests__/`, the mock relay and the web<->mobile interop peer
  (`interop/web-peer.mjs`) use them.
- **gate** Relative imports resolve, and there are no import cycles.
  Dependencies that would form one (the session needs the auth screen to
  show itself, the auth screen needs the session) are passed to factories
  as late-bound callbacks in `app.js` instead of imported.
- **gate** `app.js` stays at most 300 lines and every module under `src/`
  at most 450.
- No module under `src/` keeps mutable state at module level: each factory
  keeps its own in its closure, and what several modules share lives in
  the store.

## State

`src/app/store.js` is the one state container: the signed-in session
record, the conversation list, the message views per conversation, and the
screen's state (open tabs, the active and split panels, presence, typing,
drafts, reply drafts, searches, scroll positions, focus claims, muted
conversations, Kakao archives, sounds). Services change it and then call
`store.notify(topic)`; views subscribe in `app.js`:

| topic           | subscriber                                   |
| --------------- | -------------------------------------------- |
| `sidebar`       | `views/sidebar.js` redraws the conversation list |
| `panels`        | `views/chat-view.js` redraws the open panel(s) |
| `tabs`          | `views/tabs.js` redraws the tab strip        |
| `session-reset` | the transfer dialogs stop watching, read marks are forgotten, the frame goes back to signed-out |

Notification is synchronous, so a view redraws exactly where the change
happened, as the monolith's explicit `render*()` calls did. Unsent text
(drafts) lives only in memory; everything on disk goes through the
allowlisting serializers in `src/platform/persist.js`.

## Module map

### Bootstrap and stack

| module | role |
| ------ | ---- |
| `app.js` | loads translations, builds everything below, subscribes views to topics, mounts listeners, signs the stored identity in |
| `src/app/messaging-stack.js` | IndexedDB, the session record, the REST client, pins and trust, the direct conversations' peer bindings, the session cipher, the decrypt-once content store, secure messaging, the sender, prekey maintenance |

### Services (`src/app/services/`)

| module | role |
| ------ | ---- |
| `session.js` | register, restore, enter the app, end a session (keys kept), destroy or replace the identity |
| `messages.js` | the one ingest path from envelope to view, blob URL lifetimes, the message and conversation caches |
| `history-sync.js` | cache hydration, the conversation list, history paging, the expiry sweep, polling |
| `realtime.js` | the Socket.IO channel, its events, typing indicators sent |
| `inbound.js` | pushed messages, receipts, edits and deletions into the store |
| `outbox.js` | the sealed outbound queue: one leader tab, backoff, permanent refusals, retry of a refused send |
| `send.js` | text, reactions, edits and deletions; what a refused send tells the user |
| `attachments.js` | encrypt, upload and send images, voice notes and files |
| `identity-trust.js` | accepting or declining a changed key, safety numbers, verification, a conversation held for its handle (another account under a known handle, or a handle no server issues) |
| `device-transfer.js` | both sides of a device transfer |
| `notifications.js` | the unread count in the title, OS notifications by privacy level |
| `safety.js` | block, unblock, mute, report |
| `kakao-archives.js` | imported KakaoTalk archives |
| `preferences.js` | theme, sounds, mutes, notification level, dismissed notices (localStorage `veil-` keys) |

### Views (`src/ui/views/`)

`app-shell.js` (identity, connection pill, banners), `auth-view.js`,
`sidebar.js`, `tabs.js` (tabs, split view, list/chat switch),
`chat-view.js` (panels, header, read receipts, local history deletion),
`message-list.js` (days, groups, bubbles, media, reactions, delivery
state), `composer.js` (text, drafts, reply banner, pickers, drop),
`voice-recorder.js`, `mentions.js`, `panel-search.js`,
`message-actions.js` (context menu, delete undo), `forward-dialog.js`,
`report-dialog.js`, `key-change-banner.js`, `safety-dialog.js`,
`transfer-dialogs.js`, `new-chat-dialog.js`, `settings-dialog.js`,
`help-dialog.js`, `kakao-import.js`, `image-preview.js`, `menu.js`,
`shortcuts.js`, `notification-prompt.js`. Shared UI pieces: `src/ui/dom.js`
(`el`, avatars, illustrations), `toast.js`, `confirm.js` (themed confirm,
focus trap), `dialogs.js` (stacked dialogs), `markdown-dom.js`, `time.js`,
`sounds.js`.

### Pure logic added for the views (`src/domain/`)

`conversations.js` (peer, preview, ordering), `peer-bindings.js` (whom a
direct conversation is with, once bound, and when one is held),
`handles.js` (the handle grammar the server registers in, and how a handle
outside it is shown), `message-groups.js` (day and
sender runs, delivery state), `composer-text.js` (message cap, handle rule,
mentions), `search.js`, `delivery.js` (outbound backoff), `mute.js`,
`local-messages.js` (ids of sends the server has not named). Each has a
unit test in `__tests__/`.

## Sending a message

1. `views/composer.js` takes the text on Enter or the send button and calls
   `send.sendText(convId, text)`.
2. `services/send.js` seals it with the disappearing timer's expiry inside
   (`features/sender.js` -> `features/secure-messaging.js` `seal`): a
   session is started from the authenticated key directory if there is
   none, the peer's key checked against its pin first, and our own content
   is put in the decrypt-once store before anything is encrypted.
3. The composer clears and the optimistic view (`__pending__` id) is put in
   the store from the content we hold; `panels` redraws.
4. `sender.deliver` puts the sealed envelope (never the plaintext) in the
   outbound queue, not due for a short while, then POSTs the envelope only;
   this tab's outbox skips the entry for as long as the request is in
   flight (`sender.isInFlight`), however slow it is. On success the store's
   content is filed under the server's id, the queue entry goes and the
   delivered view replaces the pending one. On a passing failure (network,
   5xx, 429, ended session) the entry stays, and `services/outbox.js`
   drains it on reconnect and on every conversation-list load; so does a
   page that opens after one closed with
   the request in flight (the server takes a repeated client message id as
   the same message). A permanent refusal (another 4xx) drops the entry and
   marks the bubble failed; the bubble keeps the sealed envelope in memory,
   and its Retry queues that envelope again. A send that was never sealed
   (its upload or seal failed) has nothing to retry.
5. Attachments (`services/attachments.js`) first check the session can
   send, show a local bubble, seal the bytes under a fresh key
   (`crypto/attachment-v2.js`) and upload only the blob; the key and digest
   travel inside the message.

## Receiving a message

1. A push (`services/realtime.js` `message.new` -> `services/inbound.js`)
   or a history fetch (`services/history-sync.js`, paged back to what this
   device has, oldest first so each ratchet chain moves forward in order)
   hands the envelope to `messages.ingest`. A push is filed under the
   conversation id its envelope carries; a history page, and a listed last
   message, keep only the envelopes that carry the conversation they were
   fetched for, since a frame authenticates under its own conversation id
   and would otherwise show under another conversation's peer.
2. `domain/ingest.js` asks `secure.open`, which returns the content from
   the decrypt-once store or decrypts exactly once and stores the result
   before the session commits. Deleted and expired messages are retired
   there and then.
3. The view goes into the store, the conversation's last message moves,
   and `sidebar` / `panels` redraw. A hidden tab counts it in the title
   and, with permission, shows an OS notification whose content follows the
   privacy level.
4. `views/chat-view.js` marks a peer message read once half of it has been
   visible; the relay tells only the sender.

## Where trust decisions happen

- Admission is in the crypto layer, never in the UI: the session cipher
  asks the pins (`crypto/pins.js`, through `domain/peer-bindings.js`
  `createConversationVerifier`, wired in `messaging-stack.js`) before
  installing a session, before starting one from the directory, and for
  every frame it seals or opens. A key the pins do not admit records a
  pending change, and nothing is installed, opened or sealed for it; a
  conversation whose session sends to an identity the pins still admit
  goes on sending, so a forged frame stops nothing. Without a session, a
  send waits until no change is pending.
- Whom a direct conversation is with is bound the first time its crypto
  admits an identity (`domain/peer-bindings.js`, IndexedDB `direct-peers`),
  and sessions from before bindings existed are bound on the next list
  load. From then on the pins judge that conversation for the bound peer,
  and a list that names another user, or turns it into a group, changes
  only its last message and timer (`history-sync.js` `adoptConversations`).
  A conversation not bound yet is held (`peer-bindings.js` `hold`) while
  its listed handle is bound to another account, or is one no honest server
  issues (`domain/handles.js`: the server's register grammar, 3 to 32 of
  a-z, 0-9, '.' and '_', which `__tests__/handles.test.js` keeps equal to
  `register.dto.ts`). A hostile relay can list a lookalike of a known
  handle (a zero-width space, a Cyrillic letter, a trailing space) that
  renders the same and equals none; the grammar catches it where comparing
  handles cannot. A held conversation admits nothing, the pins not even
  asked, and shows a banner, a marker in its row and a frozen composer
  until the user chooses to talk to that account, which binds it. Wherever
  a conversation or a sender is named (row, tab, panel header, avatar,
  banners, safety dialog, notifications), a handle outside the grammar is
  shown with each character no handle can hold written as its code point
  (`bob[U+200B]`), so it never renders like the handle it imitates, held or
  bound. A bound conversation is shown under the handle it was bound with:
  the server never gives a user another handle (there is no rename; a
  deleted account's handle is held back for 90 days and then goes only to a
  new account, under a new user id), so a listing that names the bound user
  under another handle is the relay's, and is not shown.
- Deliberately stricter than the verdict table in
  `docs/crypto-envelope-spec.md` ("Identity trust"): a new device of a
  contact the user never verified is not pinned with a notice but held for
  review like a changed key (`NEW_DEVICE`): past the first device a
  contact is pinned with, the web admits none the user was not shown.
- The user's decisions are carried out in `services/identity-trust.js`,
  each bound to the change or key the user was shown: `accept` (refused
  with 'reverify' for a contact who was verified, or a device of theirs
  never verified), `decline` (adds no trust; refused for the key the
  session sends to), and `markVerified` for exactly the key a safety number
  was computed from. After an accept or a verification, messages locked by
  the change are opened again.
- The UI only asks and shows: `views/key-change-banner.js` (what changed,
  decline / review / compare; a held conversation, another account under
  a known handle or under one no server issues, and talking to it after a
  confirmation), `views/safety-dialog.js` (the
  number, the verification codes, mark verified), `views/chat-view.js`
  (the verified mark in the header) and `views/composer.js` (the frozen
  composer and why: a group, a legacy identity, a held conversation),
  `views/sidebar.js` (the changed-key and held-conversation markers).
- Device transfer trust: both screens show the fingerprint the server
  computes over the new device's auth and identity keys; the old device
  approves only after the user compared them, and the new device asks
  before replacing an identity stored in the browser.

## Testing

- `pnpm -C apps/web-demo test`: unit tests for crypto, domain, platform,
  features, the store and the services' pure parts.
- `npx playwright test --project=browser-unit`: protocol v2 in real Chrome
  against the in-memory relay (`e2e/mock-server.mjs`).
- `npx playwright test --project=characterization`: the whole app through
  its UI in two or more browser contexts against the same relay (its
  realtime gateway, `e2e/mock-realtime.mjs`, switched on where a test needs
  pushes), covering sign-up and sign-in, rejected sessions, wipe, settings
  and language, messaging with replies, reactions, edits, deletes,
  search, forwarding, tabs, receipts and typing, history paging,
  attachments, safety numbers, identity changes, device transfer, secret
  links and the KakaoTalk import, each with no app errors in the console;
  also what a relay that rewrites its lists cannot change, Retry of a
  refused send, and a send in flight when its page closes.
  It was written against the monolithic `app.js` and passed there before
  the split.
