# VEIL Staging Push Enable Runbook

Last updated: 2026-04-11

Use this runbook when enabling real APNs or FCM delivery in staging after
credential injection and privacy review.

This runbook is not for production.

Related docs:

- [apple-firebase-credential-setup-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/apple-firebase-credential-setup-checklist.md)
- [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)

## Preconditions

All of these must be true:

- `pnpm ci:verify` is green
- target staging env file is valid
- APNs or FCM credentials validate through `pnpm beta:push:readiness`
- payload inspection sign-off is complete
- `VEIL_PUSH_ENABLE_DELIVERY` is still `false`

## Step 1. Record the target candidate

Capture:

- commit SHA
- environment name
- chosen provider
- reviewer names for push privacy sign-off

## Step 2. Confirm readiness

Run:

```bash
pnpm beta:push:readiness -- --env-file apps/api/.env --provider apns
pnpm beta:push:readiness -- --env-file apps/api/.env --provider fcm
```

Only run the provider you actually intend to enable.

## Step 3. Flip the environment

In staging only:

- set `VEIL_PUSH_PROVIDER`
- set `VEIL_PUSH_ENABLE_DELIVERY=true`

Do not change both providers at once unless that is intentional.

## Step 4. Restart and verify API readiness

After deploy:

- call `GET /v1/health/ready`
- confirm push mode is visible and coherent
- confirm there is no production boot-guard mismatch

## Step 5. Runtime checks

Test on real devices:

- active app receives realtime first
- backgrounded app receives push wake-up
- offline then reconnected app catches up cleanly
- invalid token does not break message relay success
- repeated hints do not duplicate local messages

## Step 6. Observability checks

Confirm:

- no plaintext payload in logs
- no raw payload dump in alerts
- provider failures are coded and bounded
- reconnect/backfill still works when push is dropped

## Rollback

If any privacy or reliability issue appears:

1. set `VEIL_PUSH_ENABLE_DELIVERY=false`
2. redeploy or reload config
3. keep realtime relay active
4. capture evidence
5. do not re-enable until the issue is fixed and reviewed

## Exit criteria

This runbook is complete only when:

- staging push delivery is enabled
- privacy checks still pass
- runtime checks pass on real devices
- rollback procedure is verified
