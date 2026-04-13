# VEIL One-Day Real-Device Test Checklist

Last updated: 2026-04-08

Use this when you have one day with real devices and need the highest-signal
validation pass before or during private-beta release prep.

This is the short operational version of:

- [real-device-performance-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-execution.md)
- [real-device-performance-results-template.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-results-template.md)

## Devices

Minimum set:

- Android mid-range device
- Android flagship device
- recent iPhone

Optional:

- tablet or large-screen device for adaptive layout

## Before the day starts

1. Confirm the target commit SHA
2. Confirm the API environment and base URLs
3. Confirm which push mode is active
4. Confirm whether audited crypto is still not integrated
5. Prepare the results template for each device

## Block 1. Launch and auth

Run on every device:

- cold launch
- onboarding warning review
- create account or register test flow
- app lock enable and unlock
- background and foreground once

Record:

- cold start impression
- lock/unlock friction
- any privacy preview issue in app switcher

## Block 2. Conversation list

Run on every device:

- open with an empty or near-empty account
- open with a heavy local account state
- scroll the list quickly
- run local search by handle
- run local message result search
- tap a search result into chat

Record:

- search latency feel
- visible jank
- selection correctness on wide layouts
- whether local-only search messaging is clear

## Block 3. Chat room and history

Run on every device:

- open an active conversation
- send text while connected
- disable network temporarily and send again
- re-enable network and observe retry
- trigger resume and reconnect
- load older history
- jump into a chat from search results

Record:

- send-state clarity
- reconnect clarity
- long-history behavior
- scroll smoothness
- jump-to-context stability

## Block 4. Attachments

Run on every device:

- open attachment preview
- stage an attachment send
- interrupt network during upload
- retry upload
- cancel upload
- resolve attachment ticket and inspect download flow

Record:

- progress clarity
- failure clarity
- retry/cancel clarity
- any temp-file cleanup issue or stale state

## Block 5. Device trust flows

Run at least once across two devices:

- initiate transfer from old device
- approve on old device
- complete on new device
- verify old-device-required rule
- revoke another trusted device

Record:

- trust-state clarity
- transfer expiry clarity
- revoke impact visibility
- no-recovery message clarity

## Block 6. Accessibility and adaptive UI

Run on at least one Android and one iPhone:

- larger text setting
- screen reader spot-check
- touch-target spot-check
- landscape or wide layout where available

Record:

- truncation issues
- contrast issues
- semantic clarity
- destructive-state readability

## End-of-day outputs

Must produce:

- one filled results template per tested device
- one list of critical bugs
- one list of medium polish issues
- one go/no-go note for the next beta candidate

## Hard stop conditions

Do not call the build ready if any of these occur:

- messages are lost or duplicated under simple reconnect testing
- app lock or privacy shield fails
- transfer/revoke flow is misleading or broken
- local search or chat navigation becomes unstable on real devices
- attachment retry or cancel leaves the user confused

## Handoff back into the repo

After the day ends:

1. summarize findings by severity
2. attach the target commit SHA
3. hand the findings back for code patching
4. rerun the same checklist on the next candidate
