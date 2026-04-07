# VEIL Final Technical Status

Last updated: 2026-04-07

## Executive summary

VEIL is a strong privacy-first private beta.

It is not yet a public-production messenger, and it is not yet at the overall
technical maturity of KakaoTalk or Telegram.

What VEIL is today:

- strong private-beta architecture
- strong privacy-first product philosophy
- strong messaging reliability for private-beta scope
- strong mobile security posture for a mock-crypto private beta
- strong documentation and CI/release discipline

What VEIL is not yet:

- production-secure audited cryptography
- real push-provider-reviewed delivery at production confidence
- fully profiled real-device performance at large scale
- externally reviewed and remediated production release

## Philosophy check

VEIL's core rules remain present in the codebase and docs:

- no backup
- no recovery
- no password reset
- device-bound identity
- old-device-required trusted-device join
- ciphertext-like payloads only on the server
- no plaintext message content in backend logs
- no plaintext push payloads
- no admin message viewer
- no hidden decryption tools

Current implementation still matches that philosophy.

## What is technically strong

### Messaging engine

- idempotent send flow
- duplicate-send protection
- local outbound queue
- reconnect drain and backfill
- forward-only delivery/read receipt merging
- stale socket recovery on resume
- long-history pagination
- local search and jump-to-context for cached history

### Device model

- trusted-device graph
- explicit join from an already trusted device
- revoke and invalidation
- stale-vs-revoked trust state
- no hidden recovery fallback
- versioned local session bootstrap metadata bound to the local/remote device edge

### Attachment pipeline

- upload ticket flow
- retry/cancel handling
- failed upload cleanup
- metadata-only relay assumptions
- local temp blob lifecycle

### Mobile security

- secure storage for device/session material
- local encrypted cache key handling
- PIN verifier and biometric barrier
- privacy shield for background/app previews
- local wipe and revoke cleanup

### Release readiness

- build/lint/test gate
- policy checks
- crypto architecture checks
- deploy preflight
- beta release evidence generation
- review/performance handoff artifacts

## Why it is not yet KakaoTalk or Telegram grade

VEIL is not yet at that overall level for four main reasons:

1. Audited real crypto is not integrated yet.
2. Real APNs/FCM credentials plus privacy-reviewed delivery are not complete.
3. Real-device large-history and media performance profiling is still pending.
4. External security review has not been completed.
5. Persisted local session metadata is now migration-ready, but real audited
   session state still does not exist behind it.

Those are not cosmetic gaps. They are final production blockers.

## Current release judgment

### Private beta

Reasonable to ship as a disciplined private beta if:

- CI stays green
- deploy preflight passes for the target environment
- runtime smoke passes against the target stack
- manual QA is executed on real devices
- release notes clearly state that crypto remains mock-backed

### Public production

Not ready.

Production should remain blocked until:

- audited crypto replaces the mock boundary
- push delivery is enabled only after privacy review
- real-device performance profiling is complete
- external security review is complete

## Current external blockers

These are the main tasks that cannot be finished purely inside this repository:

1. audited real crypto adapter selection and implementation
2. APNs/FCM credential setup and provider privacy review
3. Android/iPhone real-device performance profiling
4. external security review execution

## Bottom line

VEIL is technically credible as a serious private beta.

It is not yet technically credible to claim parity with KakaoTalk or Telegram as
an overall production messenger, because the remaining blockers are exactly the
areas that separate a strong beta from a production-grade secure messenger.
