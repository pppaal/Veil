# VEIL

Production-minded private beta scaffold for a privacy-first mobile messenger.

Primary product line:
`No backup. No recovery. No leaks.`

## What this repo contains

- `apps/mobile`: Flutter mobile app shell with premium dark UI scaffolds, Riverpod state, GoRouter navigation, API-backed auth/chat flows, realtime relay wiring, app lock, transfer scaffolding, and Drift-ready local cache definitions
- `apps/api`: NestJS API with Prisma schema, challenge/verify device auth, encrypted envelope message relay, attachment ticket flow, WebSocket gateway, and old-device-required transfer flow
- `packages/shared`: shared backend-side crypto/domain abstractions and the mock crypto adapter seam
- `packages/contracts`: typed API and realtime contracts
- `infra/docker`: local Postgres, Redis, and MinIO Compose stack
- `docs`: architecture, threat model, no-recovery rationale, and system flow documentation

## Product rules

- The server never stores plaintext message bodies.
- No cloud backup exists.
- No account recovery path exists.
- No password reset exists.
- Identity is device-bound.
- Device transfer succeeds only while the old device is still available.
- Push payloads must not contain plaintext message content.
- The current crypto adapter is mock-only and not production-ready.

## Local development

1. Copy `.env.example` to `.env` and `apps/api/.env.example` to `apps/api/.env`.
2. Use Node `22.20.0` from [`.nvmrc`](c:/Users/pjyrh/OneDrive/Desktop/Veil/.nvmrc).
3. Run `pnpm install`.
4. Run `pnpm docker:up`.
5. Run `pnpm db:generate`.
6. Run `pnpm dev:api`.
7. After installing Flutter locally, run `flutter pub get` inside `apps/mobile`.
8. Run `pnpm mobile:codegen`.
9. Run `pnpm dev:mobile:api` for Android emulator wiring, or `pnpm dev:mobile:desktop` for a local Windows desktop sanity run.

For Windows desktop builds, enable Windows Developer Mode first so Flutter plugins can create symlinks.

Environment separation:
- `.env.example`: local development defaults
- `apps/api/.env.alpha.example`: internal alpha / private-beta-like container wiring
- `VEIL_PUSH_PROVIDER`: `none` by default, with `apns` or `fcm` reserved for future
  metadata-only provider wiring behind the current seam
- `VEIL_PUSH_ENABLE_DELIVERY`: `false` by default. Turning it on requires
  provider credentials and a separate privacy review.
- `VEIL_APNS_*` and `VEIL_FCM_*`: reserved provider credentials for metadata-only push wiring.
- `VEIL_ENV=production` remains intentionally blocked until audited crypto replaces the mock boundary

Mobile release identity:
- Android package: `io.veil.mobile`
- iOS bundle identifier: `io.veil.mobile`
- Android release signing reads optional `apps/mobile/android/keystore.properties`
  shaped like [keystore.properties.example](apps/mobile/android/keystore.properties.example)
  and falls back to debug signing only for local non-distributed builds

## Useful scripts

- `pnpm build`
- `pnpm lint`
- `pnpm test`
- `pnpm architecture:check`
- `pnpm ci:api`
- `pnpm ci:mobile`
- `pnpm ci:verify`
- `pnpm beta:release:check`
- `pnpm beta:release:evidence`
- `pnpm beta:deploy:preflight -- --env-file apps/api/.env`
- `apps/api/.env.alpha.example` is intentionally not deployable as-is.
  Replace placeholder secrets before running deploy preflight against a real beta env file.
- `apps/api/.env.beta.ci.example` is the non-placeholder CI fixture used to keep
  deploy preflight and beta artifact generation wired during runtime smoke.
- `pnpm beta:perf:template`
- `pnpm beta:review:manifest`
- `pnpm -C apps/api test:e2e`
- `pnpm docker:up`
- `pnpm docker:down`
- `pnpm docker:alpha:up`
- `pnpm docker:alpha:down`
- `pnpm dev:mobile:api`
- `pnpm dev:mobile:desktop`
- `pnpm mobile:analyze`
- `pnpm mobile:test`

## CI

GitHub Actions CI is defined in [`.github/workflows/ci.yml`](c:/Users/pjyrh/OneDrive/Desktop/Veil/.github/workflows/ci.yml) and runs:

- `pnpm ci:api`
- `pnpm ci:mobile`

CI is treated as a private-beta gate:
- policy checks fail on wildcard realtime CORS, missing security headers, plaintext-prone push fields, mobile console logging, and crash-reporting SDK drift
- mobile codegen, analyze, and test all run in CI
- API container builds on every main-branch and pull-request run
- main-branch runtime smoke also runs deploy preflight against the CI beta fixture,
  generates beta handoff JSON artifacts, and uploads them as workflow artifacts

## Current implementation status

- Handle registration, device registration, challenge/verify auth, conversation creation, conversation listing
- Mobile register -> challenge -> verify -> token persistence flow
- API-backed direct conversation create/list and encrypted envelope send/list flow
- Attachment upload ticket, completion, message envelope, and download-ticket resolution scaffold
- WebSocket realtime relay wiring in mobile
- Device transfer init/approve on the old device plus complete-and-authenticate on the new device with active-old-device enforcement
- Disappearing message metadata and local expiration scaffolding in mobile
- App lock with PIN/biometric hooks and security status screens
- Local privacy shield, destructive local wipe flows, and old-device revoke cleanup on mobile
- Drift-ready conversation/message cache service wired behind the messenger controller
- Versioned session-bootstrap persistence metadata wired into the local
  conversation cache for future audited crypto migration
- Docs, unit tests, and CI-friendly scripts

## Mobile runtime configuration

Flutter reads runtime endpoints through `--dart-define` flags.

- `VEIL_API_BASE_URL`: default `http://localhost:3000/v1`
- `VEIL_REALTIME_URL`: default `http://localhost:3000`

For Android emulators, use `10.0.2.2` instead of `localhost`.

## Important warning

The mock crypto adapter exists only to preserve architecture and developer workflows. It does not provide audited cryptographic security. Do not ship this code as a production messenger until the crypto layer is replaced and independently reviewed.

The API refuses to boot with `VEIL_ENV=production` while the mock crypto boundary is still wired. Private beta deployments must stay on non-production environment modes until audited crypto is integrated.

## Docs

- [Architecture](docs/architecture.md)
- [Threat Model](docs/threat-model.md)
- [No Recovery](docs/no-recovery.md)
- [Message Flow](docs/message-flow.md)
- [Local Search And History Navigation](docs/local-search-history-navigation.md)
- [Attachment Flow](docs/attachment-flow.md)
- [Device Transfer Flow](docs/device-transfer-flow.md)
- [MVP Demo Runbook](docs/mvp-demo-runbook.md)
- [Internal Alpha Deployment](docs/internal-alpha-deployment.md)
- [Internal Alpha Runbook](docs/internal-alpha-runbook.md)
- [Internal Alpha Test Checklist](docs/internal-alpha-test-checklist.md)
- [Internal Alpha Desktop QA](docs/internal-alpha-desktop-qa.md)
- [Private Beta Audit](docs/private-beta-audit.md)
- [Final Technical Status](docs/final-technical-status.md)
- [Six-Month Roadmap](docs/six-month-roadmap.md)
- [Private Beta Release Process](docs/private-beta-release-process.md)
- [Private Beta Readiness Report](docs/private-beta-readiness-report.md)
- [Private Beta Performance Profile](docs/private-beta-performance-profile.md)
- [External Security Review Packet](docs/external-security-review-packet.md)
- [Telegram-Grade Private Beta Gap Analysis](docs/telegram-grade-private-beta-gap-analysis.md)
- [Observability Hygiene](docs/observability-hygiene.md)
- [Crypto Adapter Architecture](docs/crypto-adapter-architecture.md)
- [Crypto Interoperability Fixtures](docs/crypto-interoperability-fixtures.md)
- [Trusted Device Graph](docs/trusted-device-graph.md)
- [Production Deployment Checklist](docs/production-deployment.md)
- [Mock Crypto Replacement Plan](docs/mock-crypto-replacement.md)
- [Mobile Device Security](docs/mobile-device-security.md)
