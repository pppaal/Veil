# VEIL Real-Device Performance Execution Plan

Last updated: 2026-04-07

This document is the execution checklist for the real-device performance pass
required before widening VEIL private beta distribution.

It is not a substitute for crypto review or external security review.

## Goal

Verify that VEIL behaves like a serious private messenger on real hardware under
realistic history, search, media, and reconnect pressure.

This pass must validate:

- conversation list responsiveness
- long-history chat responsiveness
- local search and jump-to-context behavior
- attachment retry/cancel behavior
- background/resume reconnect behavior
- larger-text and adaptive layout stability

## Device matrix

Minimum recommended matrix:

1. Android mid-range phone
2. Android flagship phone
3. Recent iPhone
4. One wide-layout target
   - desktop build or tablet-class screen

For each device, record:

- model
- OS version
- build identifier
- commit SHA
- VEIL env mode

## Data set requirements

Prepare a realistic local state before profiling:

- 100+ cached conversations
- one conversation with 2,000+ cached messages
- one conversation with mixed attachment states
- several pending outbound items
- several local archive search hits

## Scenarios

### 1. Cold launch

Measure:

- app launch to first interactive frame
- app launch to conversation list usable

Fail if:

- first usable state feels visibly stalled
- the app lock or privacy shield path blocks for too long after unlock

### 2. Large conversation list

Run:

- scroll through 100+ conversations
- enter and clear local search repeatedly
- switch between conversation matches and archive matches

Measure:

- conversation search latency
- visual hitching during list scroll
- result switching stability

Fail if:

- search keystrokes lag noticeably
- wide layout selection gets out of sync
- list jumps unexpectedly after result navigation

### 3. Long chat history

Run:

- open a conversation with 2,000+ cached messages
- scroll through history
- load older pages repeatedly
- repeat jump-to-context from search results

Measure:

- initial chat render time
- history append latency after pagination
- p95 scroll frame time
- jump-to-context completion time

Fail if:

- scroll hitching is obvious
- repeated jump-to-context creates duplicate or unstable message state
- older-page append reorders messages or breaks scroll position

### 4. Reconnect and resume

Run:

- disable network briefly during active chat
- queue at least one outbound message
- resume app from background
- restore network

Measure:

- reconnect time
- queued outbound drain time
- receipt catch-up behavior

Fail if:

- stale socket persists too long
- pending items appear stuck without explanation
- receipts regress or duplicate

### 5. Attachment pressure

Run:

- send 3 or more attachments
- interrupt at least one upload
- retry one failed upload
- cancel one upload

Measure:

- upload progress smoothness
- retry completion time
- cancel responsiveness
- final state clarity

Fail if:

- upload states freeze silently
- retry does not recover cleanly
- canceled temp data is not cleared locally

### 6. Accessibility and adaptive layout

Run:

- larger text sizes
- desktop/tablet split layout
- keyboard navigation where applicable

Measure:

- layout stability
- touch target clarity
- selection and focus clarity

Fail if:

- text truncation breaks critical state
- destructive actions become ambiguous
- split layout conversation selection and chat state diverge

## Metrics to record

At minimum, capture:

- `cold_start_to_interactive_ms`
- `conversation_list_ready_ms`
- `conversation_search_latency_ms`
- `archive_search_latency_ms`
- `history_append_latency_ms`
- `jump_to_context_latency_ms`
- `scroll_frame_time_p95_ms`
- `queued_drain_completion_ms`
- `attachment_retry_completion_ms`

Use the generated JSON template from:

- `pnpm beta:perf:template`
- output: `artifacts/private-beta-performance-template.json`

## Evidence required

For each device run:

- filled metric values
- short notes on visible jank or UX confusion
- screenshots or video for any failure
- commit SHA
- env mode

## Go / no-go guidance

`Go` for wider private beta if:

- list and chat stay responsive on all target devices
- reconnect behavior is understandable and bounded
- archive search and jump-to-context remain stable
- attachment retries and cancels are clear
- no major layout failures occur under larger text

`No-Go` if:

- p95 scroll frame time is consistently poor on target devices
- reconnect leaves queued items stuck
- local search or jump-to-context regularly hitch
- attachment states confuse the user under failure

## Ownership

Recommended owners:

- mobile engineer: runs build and captures traces
- QA lead: executes scenario script
- product/security lead: signs off on acceptability for wider beta

## Related docs

- [private-beta-performance-profile.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-performance-profile.md)
- [real-device-performance-results-template.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-results-template.md)
- [private-beta-release-process.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-release-process.md)
- [internal-alpha-test-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/internal-alpha-test-checklist.md)
