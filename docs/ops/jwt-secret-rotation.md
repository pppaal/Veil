# JWT Secret Rotation Runbook

The API signs access + refresh tokens with the HS256 secret in
`JWT_SECRET`. This runbook covers planned rotation and emergency
rotation (suspected leak). It is written to be runnable by any ops
engineer with production env access.

## When to rotate

- **Every 180 days** as a scheduled hygiene rotation. Calendar it.
- **Immediately** when any of:
  - a server image with `JWT_SECRET` baked in was exposed (registry
    leak, accidental commit, leaked CI artifact)
  - a compromised host with access to the API env was detected
  - the ops team cannot be certain the secret is still confidential

There is no rotation schedule gated on "time since last login" because
refresh tokens are already short-lived and access tokens even shorter.

## Prerequisites

- Write access to the production secret store (Kubernetes secret, Vault,
  AWS Secrets Manager, whatever this deployment uses).
- A deploy pipeline that can perform a rolling restart of the API.
- An ops channel to notify mobile-side on-call that a forced re-auth is
  about to land.

## Planned rotation procedure

Estimated duration: ~15 min active, ~30 min clients re-auth.

1. **Generate a new secret.**

   ```bash
   openssl rand -hex 64
   ```

   64 bytes of hex (128 chars) is overkill for HS256 but makes future
   migration to HS512 a no-op.

2. **Store it in the secret backend under a new key:**

   ```
   JWT_SECRET_NEXT = <new value>
   ```

   Do *not* overwrite `JWT_SECRET` yet.

3. **Deploy the API with dual-key acceptance** if the code supports it.
   Otherwise skip to step 4.

   If the API has been extended to accept `JWT_SECRET` + `JWT_SECRET_NEXT`
   and sign with `JWT_SECRET_NEXT`, this step is the grace window: all
   outstanding tokens still verify, but new tokens use the new key.

   For the current build, the API accepts only one key, so the rotation
   is hard: existing tokens become invalid at the moment `JWT_SECRET` is
   updated. Clients will refresh or re-auth transparently thanks to
   `401 → refresh → retry` handling.

4. **Promote the new secret.**

   Replace `JWT_SECRET` with the value of `JWT_SECRET_NEXT` in the
   production secret store.

5. **Rolling restart.**

   ```bash
   kubectl rollout restart deployment/veil-api   # or equivalent
   kubectl rollout status  deployment/veil-api
   ```

   Rolling restart avoids a cold spike — pods come up one at a time with
   the new secret.

6. **Verify.**

   ```bash
   # Fresh challenge + verify cycle should succeed:
   pnpm alpha:smoke   # from the repo root, or its prod equivalent
   ```

   Watch the `/v1/auth/verify` 401 rate in observability for 10 min. A
   brief spike is expected as clients refresh; it should drain to normal
   within one minute of the restart completing.

7. **Remove the old secret** from the secret store once verify error
   rate is back to baseline.

8. **Record** the rotation event in
   `docs/launch/release-notes/secrets-rotation-log.md`:

   ```
   YYYY-MM-DD: JWT_SECRET rotated. Reason: scheduled 180-day hygiene.
   Operator: @handle. Rollout duration: 15m. Client re-auth spike: 0.8%
   for 90s.
   ```

## Emergency rotation procedure

When a leak is suspected, every step above applies but with no grace
window. Execute as:

1. `openssl rand -hex 64` → new secret.
2. Immediately overwrite `JWT_SECRET` in the secret store.
3. `kubectl rollout restart deployment/veil-api --timeout=0s` (no wait,
   force every pod to rotate).
4. Accept the user-visible re-auth prompt. Pick your poison: a 60-second
   spike of forced re-auth beats a leaked credential.
5. Post in the security-incidents channel with the time of rotation so
   detection tooling can correlate.
6. File an incident report per `docs/launch/incident-report-template.md`
   (if/when that exists) — minimum contents: what leaked, when, how
   detected, what was rotated, exposure window.

## What does not need to rotate at the same time

Unless a leak specifically implicated them:

- APNs `.p8` — independent credential, see
  `docs/apple-firebase-credential-setup-checklist.md`
- FCM service account — independent, see same doc
- `TURN_SHARED_SECRET` — independent, see
  `docs/ops/call-infra-plan.md`
- Database credentials — independent
- S3/MinIO credentials — independent

Rotating more than is necessary creates unnecessary re-auth churn. Be
surgical.

## Validation that the rotation actually worked

- Pre-rotation: capture one known-valid token.
- Post-rotation: hit any authenticated endpoint with that pre-rotation
  token. Expect `401`. If you get `200`, the rotation did not land.
- Post-rotation: hit `/v1/auth/challenge` + `/v1/auth/verify` with a
  test device, confirm the new token works.

## Anti-patterns to avoid

- Never commit the new secret to git, even in a .env.example.
- Never base64-encode it into a container image; it must be injected at
  runtime via the secret store.
- Never rotate during a release freeze without notifying on-call; the
  re-auth spike looks like a regression to SLO dashboards.
- Never reduce the secret length to "make config lighter" — HS256
  security scales with secret entropy up to 256 bits, and we use more.
