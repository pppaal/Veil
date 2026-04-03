# VEIL Local Search And History Navigation

## Purpose

VEIL search is designed for messenger-grade usability without introducing server-side plaintext indexing.

The relay remains ciphertext-only. Search, snippets, and jump-to-context behavior happen on the trusted device using locally cached conversation state.

## What Exists Today

- Local conversation search:
  - handle
  - display name
- Local message archive search:
  - cached message text index on the current device
  - sender filter
  - date filter
  - message-type filter
  - paged local result loading for larger caches
- Search result navigation:
  - open the target conversation
  - jump to the matching cached message
  - keep surrounding message context visible
  - render result metadata and query-highlighted local snippets without sending search text to the relay
- History navigation:
  - cursor-based older-page loading
  - local scroll restoration
  - local conversation search/filter/selection restoration inside the active app session
  - adaptive split-view list + chat navigation on wider layouts

## Privacy Model

- The server does not build plaintext search indexes.
- The server does not receive plaintext search queries.
- Search snippets are generated from device-local decrypted message bodies only.
- Search results are limited to history already cached on the trusted device.
- Losing all trusted devices still means account and message access are unrecoverable.

## Local Index Architecture

Message search uses a device-local cache layer.

1. The app decrypts a message on device.
2. The decrypted body is normalized into a searchable local string.
3. That searchable body is stored in the local encrypted cache alongside the cached message record.
4. Archive search scans the local cache using:
   - conversation scope
   - sender filter
   - message type
   - date cutoff
   - local result paging cursor

This index is intentionally local-first and partial.

It is not:

- a server search feature
- a recovery mechanism
- a cross-device cloud archive

## Jump-To-Context Behavior

When the user taps a local message search result:

1. VEIL opens the target conversation.
2. VEIL makes sure the relevant cached page is present locally.
3. VEIL scrolls to the target message.
4. VEIL briefly highlights the target bubble.

The chat is not forced into a filtered-only search view. The goal is context, not just result isolation.

Repeated selection of the same result issues a fresh local navigation request so the jump and highlight can replay in split-view layouts.

## Search Result Paging

Search results are paged on-device.

- The first pass returns only a bounded slice of matches.
- Additional results are requested with a local cursor based on the last result timestamp and id.
- This avoids rendering or scanning the full visible result set into the UI all at once.
- The conversation list keeps its local query, filters, selected conversation, and scroll position while the active app session remains alive.

## History And Pagination

- Conversation history remains ordered by conversation order when available.
- Older pages are fetched incrementally from the relay using opaque metadata cursors.
- Scroll offset is restored locally by Flutter page storage.
- Cached search results can point into older history already stored on the device even before a new backfill fetch happens.

## Local Index Lifecycle

The search index lives and dies with the trusted device state.

It is created when:

- a cached message is decrypted locally
- searchable body text is written into the encrypted local cache

It is removed when:

- local wipe runs
- revoke-triggered local cleanup runs
- the app clears cached conversations/messages
- message expiration removes the message locally

## What Can Stay The Same For Real Crypto

- search remains local-only
- server remains ciphertext-only
- jump-to-context UX remains valid
- history pagination and scroll restoration remain valid

## What Will Need Review For Real Crypto

- how searchable bodies are derived from audited decrypted payloads
- how local session-state encryption interacts with the cache
- whether a stronger local full-text index is needed for large archives
- how per-device joined history affects local search scope in a trusted-device graph

## Known Beta Limits

- Search only covers history cached on the current trusted device.
- There is no full encrypted archive index yet for arbitrarily large long-term history.
- Search snippets are text-only and do not parse rich reply/reference metadata.
- Jump-to-reply is not implemented because reply linkage is not part of the current message model.
