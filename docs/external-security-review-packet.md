# VEIL External Security Review Packet

This packet is the minimum handoff set for a serious external review of the VEIL private beta.

It does not claim production cryptographic safety.

## Scope statement

Review the current VEIL private beta as:

- a privacy-first mobile messenger
- a trusted-device graph product
- a ciphertext-only relay architecture
- a production crypto implementation (X25519+AES-256-GCM) with a strict adapter boundary

Do not treat the current build as externally audited production E2EE until the external review is complete.

## Required packet contents

1. Product philosophy and non-negotiables
   - [no-recovery.md](docs/no-recovery.md)
   - [trusted-device-graph.md](docs/trusted-device-graph.md)
2. System and threat model
   - [architecture.md](docs/architecture.md)
   - [threat-model.md](docs/threat-model.md)
3. Messaging, transfer, and attachment flows
   - [message-flow.md](docs/message-flow.md)
   - [device-transfer-flow.md](docs/device-transfer-flow.md)
   - [attachment-flow.md](docs/attachment-flow.md)
4. Local security and observability posture
   - [mobile-device-security.md](docs/mobile-device-security.md)
   - [observability-hygiene.md](docs/observability-hygiene.md)
5. Crypto boundary and migration posture
   - [crypto-adapter-architecture.md](docs/crypto-adapter-architecture.md)
   - [mock-crypto-replacement.md](docs/mock-crypto-replacement.md)
   - [audited-crypto-adapter-execution.md](docs/audited-crypto-adapter-execution.md)
6. Release posture and known limits
   - [private-beta-audit.md](docs/private-beta-audit.md)
   - [private-beta-readiness-report.md](docs/private-beta-readiness-report.md)
   - [production-deployment.md](docs/production-deployment.md)
   - [push-privacy-review-checklist.md](docs/push-privacy-review-checklist.md)

## Questions the review must answer

1. Does the current architecture preserve:
   - no backup
   - no recovery
   - device-bound identity
   - old-device-required join
   - ciphertext-only server handling
2. Are there any paths that could leak plaintext through:
   - logs
   - push payloads
   - temp files
   - local cache
   - admin/debug tooling
3. Are revoke, transfer expiry, and stale-device handling strong enough for private beta?
4. Is the crypto adapter boundary strict enough to support audited replacement without reworking product logic?

## Evidence to provide alongside docs

- latest green CI run
- latest `pnpm beta:release:check` result
- latest `artifacts/private-beta-release-evidence.json`
- latest `artifacts/external-security-review-manifest.json`
- latest `artifacts/external-review-findings-template.json`
- exact commit SHA under review
- environment mode used for the review build
- current mobile build artifact identifiers

## Findings handling

When findings arrive:

1. record them in
   [external-review-remediation-tracker.md](docs/external-review-remediation-tracker.md)
2. patch the repo
3. re-run verification
4. attach retest evidence

## Machine-readable artifacts

- `pnpm beta:external:bundle` generates all handoff artifacts
- `pnpm beta:production:blockers` generates the production blockers report
- `artifacts/external-security-review-manifest.json`: review scope and file inventory
- `artifacts/external-review-findings-template.json`: structured findings template with severity and status fields
- `artifacts/private-beta-release-evidence.json`: CI and verification evidence
- `artifacts/production-blockers-report.json`: current production blocker summary

## Explicit caveats

- Production crypto adapter (LibCryptoAdapter) is integrated but not yet externally audited.
- Push providers remain metadata-only seams unless a separate privacy review is attached.
- Production boot remains blocked until external cryptographic audit is complete.

## Recent changes since last packet (Phase Q-U, 2026-04)

The following changes landed after the prior packet snapshot. The auditor
should focus on these in addition to the regular scope.

### Authentication and session lifecycle (Phase R)

- `auth.service.ts`: `ACCESS_TOKEN_TTL_SECONDS` reduced from `60*60*12`
  (12h) to `60*60` (1h). Refresh tokens unchanged at 30d. Reduces blast
  radius of access-token theft. Refresh remains atomic (Redis `GETDEL`).
- `auth.service.verify` and `auth.service.refresh` now also reject when
  `device.user.status !== 'active'`. Previously a soft-suspended user could
  still mint new access tokens until natural expiry.
- `jwt-auth.guard.ts`: every request re-asserts `device.user.status ===
  'active'` (in addition to `device.isActive` and `!revokedAt`).
- `register.dto.ts`: handle regex hardened — disallows leading/trailing
  separators and consecutive `.` or `_` (homograph reduction).
- `register.dto.ts`: `signedPrekeyBundle` and `publicIdentityKey` now
  validated as base64url (`^[A-Za-z0-9_-]+={0,2}$`).

### Throttling and ingress (Phase R)

- New `cf-throttler.guard.ts` replaces the default `ThrottlerGuard`.
  Tracker preference order: `cf-connecting-ip`, then JWT-bound
  `auth.deviceId`, then `x-forwarded-for`, then `req.ip`. Required because
  behind a Cloudflare Tunnel sidecar all requests share the loopback
  address and would collapse into a single bucket.
- `users.controller.ts`: `/users/:handle` and `/users/:handle/key-bundle`
  dropped from 60/min to 10/min unauthenticated. Mitigates handle
  enumeration.

### Logging and storage hygiene (Phase R)

- `logging.interceptor.ts`: redacts the `:handle` segment of `/users/:handle`
  and any UUID-shaped path segment before emitting per-request logs.
- `update-profile.dto.ts`: strips `\x00-\x1F`, `\x7F-\x9F`, BiDi/format
  marks (ZWSP/ZWNJ/LRM/RLM/LRE/RLE/PDF/LRO/RLO/WJ/BOM) from `displayName`,
  `bio`, `statusMessage`, `statusEmoji` to block invisible-text spoofing.
- `attachment-storage.gateway.ts`: split TTL — uploads remain 600s, but
  presigned download URLs drop to 90s.
- `profile.service.getProfile`: replaced unconditional `upsert` with
  `findUnique` + `create` fallback. Cosmetic but reduces write traffic.

### Device transfer (Phase U)

- `device-transfer.service.complete` now atomically revokes the old
  device inside the same serializable transaction that creates the new
  device: `isActive=false`, `revokedAt=completedAt`, `pushToken=null`.
  The completion response sets `revokedDeviceId` accordingly. After tx
  commit, `realtimeGateway.disconnectDevice(oldDeviceId)` cuts any in-
  flight WS so the old device cannot continue receiving envelopes.
- New `GET /device-transfer/sessions/:sessionId` (JWT-authed, owner-only).
  Returns `pending|claimed|approved|completed|expired` plus the pending
  claim's `claimantFingerprint`. The new device polls `/complete` instead
  of this endpoint and rides on the same auth proof — server returns 403
  `transfer_approval_required` until the old device approves.

### Mobile platform posture (Phase T)

- `apps/mobile/android/app/build.gradle.kts`: release builds now fail
  loud when `keystore.properties` is absent — no silent fallback to the
  debug keystore. R8 minify/shrink plus a `proguard-rules.pro` keep
  set were added.
- `apps/mobile/ios/Runner.xcodeproj`: `IPHONEOS_DEPLOYMENT_TARGET`
  bumped 13.0 → 14.0.
- `apps/mobile/ios/Runner/AppDelegate.swift`: dropped the `cydia://`
  `canOpenURL` jailbreak probe — needs `LSApplicationQueriesSchemes`
  to actually return true and that listing draws extra App Review
  scrutiny. Filesystem and dyld-image probes remain.
- `apps/mobile/lib/src/core/notifications/push_token_coordinator.dart`:
  `debugPrint` replaced with `developer.log` so `policy-check.mjs` (which
  forbids ad-hoc `print`/`debugPrint`) passes.

### Operational documentation (Phase T)

- `docs/cloudflare-tunnel-deploy.md`: added pg_dump cron snippet (daily,
  14-day retention) with privacy callout — snapshots include handle
  metadata even though message bodies remain ciphertext.
- `docs/ops/abuse-triage.md`: new runbook. SQL queries omit the
  `messages.ciphertext` column entirely. Suspend uses
  `users.status='suspended'`; the JwtAuthGuard `status==='active'` check
  enforces.
- `docs/tester-guide-ko.md`: tester-facing FAQ.
- `scripts/demo-status.mjs` + `pnpm demo:status`: probes API
  health and the postgres/redis/minio/api/cloudflared containers.

### Verification

- `pnpm test` (apps/api): 132/132 passing as of Phase U.
- `pnpm test:e2e` (apps/api): 6/6 passing.
- `node scripts/policy-check.mjs`: passing.
