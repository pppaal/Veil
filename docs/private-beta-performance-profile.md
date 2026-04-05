# VEIL Private Beta Performance Profile

This document defines the minimum real-device profiling pass before widening VEIL private beta distribution.

It is a performance and UX checklist, not a cryptographic review.

Machine-readable template:
- `pnpm beta:perf:template`
- output: `artifacts/private-beta-performance-template.json`

## Target areas

1. Conversation list
   - cold launch to usable list
   - local search latency
   - large list scroll smoothness
2. Chat room
   - first render of long history
   - older-history pagination
   - jump-to-context behavior
   - repeated search-result jumps
3. Messaging reliability
   - reconnect after short network loss
   - queued outbound drain time
   - delivery/read badge updates
4. Attachments
   - staged -> uploading -> finalizing transitions
   - retry after failure
   - cancel responsiveness
5. Adaptive layouts
   - desktop / tablet split view
   - narrow layout search and navigation return path

## Suggested device matrix

- Android mid-range device
- Android flagship device
- iPhone recent generation
- one desktop or tablet-class layout target

## Scenarios to profile

### A. Large conversation list

- 100+ cached conversations
- query and clear search repeatedly
- switch between local conversation and message search results

### B. Long history

- 2,000+ cached messages in one conversation
- load older pages multiple times
- jump into a cached search result near the middle of history
- return to the list and repeat

### C. Attachment queue pressure

- 3+ pending attachments in mixed states
- temporary network loss during upload
- retry and cancel flows

## Metrics to record

- cold start to first interactive frame
- search result latency for local conversation search
- search result latency for local archive search
- page fetch to visible history append time
- average and p95 frame time in long chat scroll
- attachment retry completion time after reconnect

## Pass / fail guidance

Pass for private beta if:

- the list and chat remain responsive under realistic cache sizes
- reconnect and backfill remain understandable and bounded
- attachment states do not stall silently
- no layout collapses occur under larger text sizes

No-go for wider beta if:

- search or jump-to-context causes repeated jank
- long chat scroll shows visible hitching on target devices
- reconnect causes duplicate state or unread/read badge drift
- attachment states appear stuck without clear recovery action
