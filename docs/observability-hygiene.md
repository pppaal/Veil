# VEIL Observability Hygiene

VEIL treats observability as a privacy boundary, not a convenience layer.

## Goals

- No plaintext message content in logs, alerts, traces, or push payloads
- No secrets in request or error telemetry
- No crash-reporting SDKs until event scrubbing and review are complete
- No production claims while mock crypto remains active

## Backend logging rules

- Request logs may include:
  - `requestId`
  - method
  - path
  - status code
  - actor user id
  - duration
- Request logs must not include:
  - ciphertext
  - nonce
  - transfer tokens
  - signatures
  - upload or download URLs
  - auth public/private material
  - push tokens
- All backend metadata flows through the redaction layer in [app-logger.service.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/src/common/logger/app-logger.service.ts).

## Mobile logging rules

- `print()` and `debugPrint()` are blocked by policy checks inside `apps/mobile/lib`.
- UI error states must use normalized user-facing messages instead of raw exception dumps.
- No analytics SDKs are wired into the current private-beta branch.

## Push and alerting rules

- Push payloads remain metadata-only.
- Alerts should key on error codes, health checks, queue growth, and storage failures.
- Alerts must not contain:
  - message body fields
  - ciphertext blobs
  - nonces
  - transfer payloads
  - signed URLs

## Crash reporting posture

- `firebase_crashlytics` and `sentry_flutter` are intentionally absent.
- If crash reporting is introduced later, it must ship with:
  - payload scrubbing
  - attachment and auth field redaction
  - private-beta review sign-off
  - updated policy checks

## CI enforcement

Policy checks in [policy-check.mjs](c:/Users/pjyrh/OneDrive/Desktop/Veil/scripts/policy-check.mjs) currently enforce:

- no wildcard realtime CORS
- security headers in API bootstrap
- metadata-only push payload patterns
- logger redaction presence
- no mobile console logging
- no crash-reporting SDK drift

## Remaining risks

- External log sinks and alert routing are not yet integrated in this repo.
- Future tracing or crash tooling can regress privacy if added without policy updates.
- Mock crypto remains active, so observability review is necessary but not sufficient for production release.
