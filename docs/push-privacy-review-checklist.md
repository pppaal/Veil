# VEIL Push Privacy Review Checklist

Last updated: 2026-04-07

This checklist is required before enabling:

- `VEIL_PUSH_PROVIDER=apns`
- `VEIL_PUSH_PROVIDER=fcm`
- `VEIL_PUSH_ENABLE_DELIVERY=true`

The goal is delivery reliability without plaintext leakage.

## Scope

Review the current metadata-only push path implemented behind:

- [push.service.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/src/modules/push/push.service.ts)
- [apns-push.provider.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/src/modules/push/apns-push.provider.ts)
- [fcm-push.provider.ts](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/src/modules/push/fcm-push.provider.ts)

The review is not optional.

## Allowed payload contract

Push hints may contain only metadata required to wake the client:

- `kind`
- `messageId`
- `conversationId`
- `serverReceivedAt`

Push payloads must not include:

- plaintext message body
- plaintext attachment names or captions
- ciphertext blobs
- nonces
- attachment keys
- transfer tokens
- auth challenge material
- handle search text

## Phase 1: credential readiness

Quick machine check:

- `pnpm beta:push:readiness`
- `pnpm beta:push:readiness -- --env-file apps/api/.env --provider apns`
- `pnpm beta:push:readiness -- --env-file apps/api/.env --provider fcm`

Artifact written:

- `artifacts/push-provider-readiness.json`

### APNs

Required:

- Apple Developer access
- `io.veil.mobile` bundle identifier
- Push Notifications capability
- APNs auth key
- team id
- key id
- secure storage for the private key

### FCM

Required:

- Firebase project
- Android app registration
- iOS app registration
- service account JSON with messaging access
- secure storage for service account material

`No-Go` if:

- credentials are stored in source control
- bundle/app identifiers do not match shipping builds
- staging and beta credentials are mixed

## Phase 2: payload inspection

Required checks:

- inspect actual APNs request body
- inspect actual FCM request body
- verify only allowed metadata fields are present
- verify notification title/body fields are absent
- verify background wake-up shape only

Evidence to capture:

- redacted request sample for APNs
- redacted request sample for FCM
- reviewer sign-off that plaintext fields are absent

## Phase 3: provider-side exposure review

Required checks:

- Apple/Firebase dashboards do not expose plaintext message content
- provider error logs do not include sensitive fields beyond the allowed metadata
- internal alerting and retry logs do not echo payloads unsafely

`No-Go` if:

- provider tooling stores or displays plaintext body fields
- application logs include raw push payload dumps

## Phase 4: runtime verification

Required staging tests:

- recipient app in background receives wake-up hint
- recipient app offline then online receives wake-up hint
- invalid token handling does not break relay delivery
- provider failure does not break API message success path
- repeated hints do not create duplicate local messages

Related runtime expectations:

- push failure is non-blocking for the message relay path
- realtime remains primary
- push remains fallback only

## Phase 5: observability review

Check against:

- [observability-hygiene.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/observability-hygiene.md)

Required:

- no plaintext fields in logs
- no raw provider payloads in traces
- no crash-reporting SDK drift
- alert text uses coded failures, not payload dumps

## Enablement checklist

All of the following must be true before enabling delivery:

- credentials are injected through secrets, not committed files
- payload inspection sign-off is complete
- provider-side exposure review is complete
- staging runtime verification is complete
- observability review is complete
- exact commit SHA under review is recorded

Then and only then:

- set `VEIL_PUSH_PROVIDER`
- set `VEIL_PUSH_ENABLE_DELIVERY=true`

## Post-enable verification

Within the first rollout window:

- monitor provider error rate
- monitor invalid token rate
- verify no plaintext appears in logs or alerts
- verify reconnect/backfill still handles dropped pushes correctly

If any of these fail:

- disable `VEIL_PUSH_ENABLE_DELIVERY`
- preserve realtime relay path
- investigate before re-enabling

## Explicit non-claims

Even after enablement:

- push is still metadata-only fallback, not a trusted message transport
- push privacy review does not replace external cryptographic audit
- push enablement does not justify a production-security claim without completed external review
