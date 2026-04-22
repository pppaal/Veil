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
- Production crypto (`LibCryptoAdapter`, X25519 + AES-256-GCM + Double Ratchet) is wired by default; `VEIL_ENV=production` remains blocked until the adapter is externally audited.

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
- `VEIL_ENV=production` requires `VEIL_AUDITED_CRYPTO_ATTESTED=true`; the flag must only be set after external crypto audit completes and its findings are remediated

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
- `pnpm beta:push:readiness`
- `pnpm beta:external:bundle`
- `pnpm beta:external:status`
- `apps/api/.env.alpha.example` is intentionally not deployable as-is.
  Replace placeholder secrets before running deploy preflight against a real beta env file.
- `apps/api/.env.beta.ci.example` is the non-placeholder CI fixture used to keep
  deploy preflight and beta artifact generation wired during runtime smoke.
- `pnpm beta:perf:template`
- `pnpm beta:review:manifest`
- `pnpm beta:production:blockers`
- `pnpm format:check`
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
- format check runs on every push and pull request
- policy checks fail on wildcard realtime CORS, missing security headers, plaintext-prone push fields, mobile console logging, and crash-reporting SDK drift
- mobile codegen, analyze, and test all run in CI
- API container builds on every main-branch and pull-request run
- main-branch runtime smoke also runs deploy preflight against the CI beta fixture,
  generates beta handoff JSON artifacts and the production blockers report, and uploads them as workflow artifacts

## Current implementation status

### Cryptography
- Production `LibCryptoAdapter` (adapter id `lib-x25519-aes256gcm-v2`): X25519 ECDH + AES-256-GCM + HKDF-SHA256, Ed25519 device identity signing
- Full Double Ratchet (DH ratchet + symmetric hash ratchet) gives forward secrecy and post-compromise security
- Wire format is pinned by Flutter tests in [`crypto_envelope_pinning_test.dart`](apps/mobile/test/crypto_envelope_pinning_test.dart) and specified in [`docs/crypto-envelope-spec.md`](docs/crypto-envelope-spec.md)
- Production boot is gated on `VEIL_AUDITED_CRYPTO_ATTESTED=true`; external audit has not yet happened, so the flag stays false and `VEIL_ENV=production` is blocked

### Core messaging
- Handle registration, device registration, challenge/verify auth, conversation creation, conversation listing
- Mobile register -> challenge -> verify -> token persistence flow
- API-backed direct and group conversation create/list and encrypted envelope send/list flow
- Attachment upload ticket, completion, message envelope, and download-ticket resolution, with type-aware UI rendering and file-size formatting
- WebSocket realtime relay wiring in mobile with typing indicators and online presence fan-out
- Device transfer init/approve on the old device plus complete-and-authenticate on the new device with active-old-device enforcement
- Disappearing message metadata and local expiration scaffolding in mobile
- App lock with PIN/biometric hooks and security status screens
- Local privacy shield, destructive local wipe flows, and old-device revoke cleanup on mobile
- Drift-ready conversation/message cache service wired behind the messenger controller
- Versioned session-bootstrap persistence metadata wired into the local conversation cache

### X-chat level features
- **Group chat** (wired end-to-end): group conversation type, group metadata (name, description, avatar, member limit, invite link), member roles (owner/admin/member), per-pair ratchet fan-out
- **Channels** (scaffold): broadcast channel type, subscriber model, public/private channels
- **Voice messages**: recording UI with waveform visualization, playback preview, send/cancel flow
- **Media messages**: photo/video picker with grid selection, camera scaffold, encrypted upload pipeline
- **Voice/Video calls** (UI scaffold): full call screen with dialing/ringing/connected/ended states, call timer, mute/speaker/video controls, call history
- **Stories/Moments**: 24-hour expiring stories, story circles with unseen indicators, full-screen story viewer with auto-advance, story feed
- **Contacts**: device-local contact list with search, alphabetical sections, start-chat and view-profile actions wired to the real API
- **Profile**: editable profile with display name, bio, status message, avatar, privacy metrics
- **AI assistant** (stub): on-device AI chat shell that returns static helper messages
- **Stickers & Emoji** (picker only): emoji picker with categories and search, sticker pack and GIF placeholders
- **Reactions**: quick-reaction picker (6 common emoji), expandable to full emoji set
- **Message replies**: reply-to-message reference in message model
- **Bottom navigation**: 4-tab main shell (Chats, Contacts, Stories, Calls)

### Design notes not yet implemented
- [Open chat (phone-number-free group rooms)](docs/open-chat-design.md) — Phase 1 MVP design landed; schema, API, and client work deferred until the design is accepted
- [Forward-secrecy ratchet design](docs/forward-secrecy-ratchet-design.md) — background note that informed the v2 Double Ratchet upgrade

### Infrastructure
- Docs, unit tests, and CI-friendly scripts

## Mobile runtime configuration

Flutter reads runtime endpoints through `--dart-define` flags.

- `VEIL_API_BASE_URL`: default `http://localhost:3000/v1`
- `VEIL_REALTIME_URL`: default `http://localhost:3000`

For Android emulators, use `10.0.2.2` instead of `localhost`.

## Important warning

The production crypto adapter (X25519 + AES-256-GCM + Double Ratchet) is wired and its wire format is pinned by tests, but it has **not been externally audited** yet. Do not ship this code as a public messenger until independent cryptographic review is complete and its findings are remediated.

The API refuses to boot with `VEIL_ENV=production` unless `VEIL_AUDITED_CRYPTO_ATTESTED=true` is set. Setting that flag is an explicit attestation that external audit has completed and findings have landed — it must not be flipped to unblock development or internal alpha. Private beta deployments stay on non-production environment modes.

The legacy `MockCryptoAdapter` still exists in the tree for historical tests but is no longer instantiated at app bootstrap.

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
- [Real-Device Performance Execution Plan](docs/real-device-performance-execution.md)
- [Real-Device Performance Results Template](docs/real-device-performance-results-template.md)
- [Real-Device Performance Triage Guide](docs/real-device-performance-triage-guide.md)
- [External Security Review Packet](docs/external-security-review-packet.md)
- [External Security Review Request Template](docs/external-security-review-request-template.md)
- [External Review Intake Checklist](docs/external-review-intake-checklist.md)
- [External Execution Master Checklist](docs/external-execution-master-checklist.md)
- [External Review Remediation Tracker](docs/external-review-remediation-tracker.md)
- [Audited Crypto Adapter Execution Plan](docs/audited-crypto-adapter-execution.md)
- [Audited Crypto Library Decision](docs/audited-crypto-library-decision.md)
- [Crypto Envelope Spec](docs/crypto-envelope-spec.md)
- [Crypto Mobile Bridge Design](docs/crypto-mobile-bridge-design.md)
- [Crypto Session State Migration](docs/crypto-session-state-migration.md)
- [Forward Secrecy Ratchet Design](docs/forward-secrecy-ratchet-design.md)
- [Open Chat Design (draft)](docs/open-chat-design.md)
- [Launch Runbook](docs/launch-runbook.md)
- [External Audit Outreach Template](docs/external-audit-outreach-template.md)
- [Privacy Policy — English](docs/privacy-policy-en.md)
- [Privacy Policy — Korean](docs/privacy-policy-ko.md)
- [Push Privacy Review Checklist](docs/push-privacy-review-checklist.md)
- [Apple And Firebase Credential Setup Checklist](docs/apple-firebase-credential-setup-checklist.md)
- [Staging Push Enable Runbook](docs/staging-push-enable-runbook.md)
- [One-Day Real-Device Test Checklist](docs/one-day-real-device-test-checklist.md)
- [Telegram-Grade Private Beta Gap Analysis](docs/telegram-grade-private-beta-gap-analysis.md)
- [Observability Hygiene](docs/observability-hygiene.md)
- [Crypto Adapter Architecture](docs/crypto-adapter-architecture.md)
- [Crypto Interoperability Fixtures](docs/crypto-interoperability-fixtures.md)
- [Trusted Device Graph](docs/trusted-device-graph.md)
- [Production Deployment Checklist](docs/production-deployment.md)
- [Mock Crypto Replacement Plan](docs/mock-crypto-replacement.md)
- [Mobile Device Security](docs/mobile-device-security.md)
- [Mobile Design System](docs/mobile-design-system.md)
