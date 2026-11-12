# VEIL Observability Hygiene

VEIL treats observability as a privacy boundary, not a convenience layer.

## Goals

- No plaintext message content in logs, alerts, traces, or push payloads
- No secrets in request or error telemetry
- No crash-reporting SDKs until event scrubbing and review are complete
- No audited-security or production claims while the external cryptographic audit remains pending

## Backend logging rules

- Request logs may include:
  - `requestId`
  - method
  - route template (`/v1/users/:handle`), never the concrete path or query
  - status code
  - duration
  - on 5xx only: `actorRef`, a pseudonym (first 16 hex chars of
    HMAC-SHA256 under a random in-memory key that is replaced every UTC
    day). It lets operators group one actor's failures within a day; it
    cannot be joined to a user id, or across days, from the logs alone.
- Request logs must not include:
  - the raw URL, path parameters (handles, ids) or query strings
  - user ids or device ids
  - ciphertext
  - nonce
  - transfer tokens
  - signatures
  - upload or download URLs
  - auth public/private material
  - push tokens (UnifiedPush endpoints included; delivery failures log only an
    error code or HTTP status class)
- The route template comes from Express's matched route
  (`req.baseUrl + req.route.path`, see
  [request-redactor.ts](apps/api/src/common/logger/request-redactor.ts)).
  Unmatched requests log `unmatched`. Earlier regex redaction of the raw URL
  was silently defeated by the `/v1` prefix and leaked handles.
- Prisma errors are logged as class name and error code only; their messages
  can embed query arguments.
- All backend metadata flows through the redaction layer in [app-logger.service.ts](apps/api/src/common/logger/app-logger.service.ts).
  It is the only place that writes logs: `scripts/policy-check.mjs`
  (`logging-through-app-logger`) rejects a raw Nest `Logger` or `console`
  call anywhere else in `apps/api/src`. Callers log an event name with
  chosen fields; an `Error` object passed as a field keeps its message, so
  failure paths log `{ name, code }` instead, built by
  `common/logger/describe-failure.ts` (see `AccountService`, whose deletion
  failures once logged the account id and raw Prisma error text, and
  `PushService`, whose delivery failures once logged the push provider's
  response text). Push providers give their errors a code that names only the
  provider and the HTTP status or socket error (`apns_status_410`,
  `fcm_status_404`, `unifiedpush_status_5xx`).

## Metrics rules

- HTTP metrics are labelled by method, route template and status class. The
  route template bounds label cardinality by the number of routes, so no
  handle, id or token can become a label value.
- No metric is labelled with user, device or conversation identifiers.

## Edge proxy logs

- Caddy's access log ([Caddyfile](infra/caddy/Caddyfile)) deletes
  `request>remote_ip`, `request>client_ip`, the URI, and all request headers,
  with `Authorization`, `X-Forwarded-For` and `Cf-Connecting-Ip` named
  explicitly so they stay deleted if the blanket rule is ever narrowed.

## Mobile logging rules

- `print()` and `debugPrint()` are blocked by policy checks inside `apps/mobile/lib`.
- UI error states must use normalized user-facing messages instead of raw exception dumps.
- No analytics SDKs are wired into the current private-beta branch.

## Push and alerting rules

- Push payloads remain metadata-only.
- `VEIL_PUSH_PROVIDER` may select `none`, `apns`, `fcm` or `unifiedpush`, but every
  provider must stay behind the seam in [push.service.ts](apps/api/src/modules/push/push.service.ts).
- `VEIL_PUSH_ENABLE_DELIVERY` must stay `false` until provider credentials are
  configured and the specific provider path has passed privacy review.
- The review process is defined in
  [push-privacy-review-checklist.md](docs/push-privacy-review-checklist.md).
- Provider selection does not authorize plaintext payload fields. The payload
  contract stays metadata-only regardless of provider kind.
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

Policy checks in [policy-check.mjs](scripts/policy-check.mjs) currently enforce:

- no wildcard realtime CORS
- security headers in API bootstrap
- metadata-only push payload patterns
- logger redaction presence
- no mobile console logging
- no crash-reporting SDK drift
- no `request.url` / `req.url` in the logging interceptor or exception filter
- the authentication guard runs before the throttler, so rate limits key on
  devices rather than shared IPs
- Caddy strips client-supplied `CF-Connecting-IP` on every proxy and deletes
  client addresses from its access log

Before checking the repository, the script runs a self-test: it seeds one
violation per rule into a temporary tree and fails if any of them passes, so
a rule that silently stopped matching is caught in CI.

## Remaining risks

- External log sinks and alert routing are not yet integrated in this repo.
- Future tracing or crash tooling can regress privacy if added without policy updates.
- The production crypto adapter (`LibCryptoAdapter`) is active but not yet externally audited, so observability review is necessary but not sufficient for production release.
