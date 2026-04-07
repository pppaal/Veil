# VEIL Real-Device Performance Results Template

Last updated: 2026-04-07

Use this template to record an actual VEIL performance run on real devices.

Related execution plan:
- [real-device-performance-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-execution.md)

## Run metadata

- Date:
- Commit SHA:
- App build identifier:
- Environment mode:
- Tester:

## Device

- Device model:
- OS version:
- Build target:
  - Android / iPhone / desktop / tablet
- Network condition:
  - Wi-Fi / LTE / throttled / offline-reconnect

## Dataset

- Cached conversations count:
- Largest conversation cached message count:
- Pending outbound count:
- Attachment draft count:
- Larger text enabled:
  - yes / no

## Scenario results

### 1. Cold launch

- cold_start_to_interactive_ms:
- conversation_list_ready_ms:
- Notes:
- Pass / fail:

### 2. Large conversation list

- conversation_search_latency_ms:
- archive_search_latency_ms:
- Observed scroll jank:
  - none / minor / moderate / severe
- Notes:
- Pass / fail:

### 3. Long history

- history_append_latency_ms:
- jump_to_context_latency_ms:
- scroll_frame_time_p95_ms:
- Repeated jump-to-context stable:
  - yes / no
- Notes:
- Pass / fail:

### 4. Reconnect and resume

- queued_drain_completion_ms:
- receipt catch-up stable:
  - yes / no
- Duplicate state seen:
  - yes / no
- Notes:
- Pass / fail:

### 5. Attachments

- attachment_retry_completion_ms:
- cancel responsiveness:
  - instant / acceptable / poor
- Silent stuck state seen:
  - yes / no
- Notes:
- Pass / fail:

### 6. Accessibility and adaptive layout

- larger-text layout stable:
  - yes / no
- split-layout selection stable:
  - yes / no
- destructive actions still clear:
  - yes / no
- Notes:
- Pass / fail:

## Overall summary

- Overall pass / fail:
- Biggest issue found:
- Severity:
  - blocker / major / moderate / minor
- Recommended action:

## Evidence

- Screenshot paths:
- Video paths:
- Trace/profiling artifact paths:
- Linked JSON artifact:
  - `artifacts/private-beta-performance-template.json`
