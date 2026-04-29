# VEIL

Privacy-first end-to-end encrypted messenger.

> **No backup. No recovery. No leaks.**

The design premise is the inverse of mainstream messengers: there is no
backup path, no password reset, no admin override, and no plaintext on
the server. Lose the device or wipe the browser, and the conversation
is gone for good. That tradeoff is the product.

The "no recovery" rule is not just documentation — it is encoded in
[`scripts/policy-check.mjs`](scripts/policy-check.mjs) as a CI gate that
fails the build on any commit that introduces a recovery flow, an admin
message viewer, plaintext in push payloads, wildcard CORS, or ad-hoc
console logging in mobile.

---

## What this repo contains

| Path | Description |
|---|---|
| `apps/api/` | NestJS backend — 19 modules, 132 unit + 6 e2e tests, 10 Prisma migrations |
| `apps/mobile/` | Flutter app (iOS + Android) with full Signal-style double ratchet (`LibCryptoAdapter`) |
| `apps/web-demo/` | Vanilla-JS web client — full feature surface incl. voice messages, reactions, reply/edit/delete |
| `packages/contracts/` | Typed API + realtime contracts (single source of truth) |
| `packages/shared/` | Shared envelope versions and protocol constants |
| `infra/caddy/` | Production TLS reverse proxy |
| `infra/prometheus/` `grafana/` | Metrics + alerting + 8-panel dashboard, all auto-provisioned |
| `infra/docker/` | Demo / alpha / production Compose stacks |
| `docs/` | 50+ documents — architecture, threat model, runbooks, crypto specs, audit handoff |
| `scripts/` | CI gates, release evidence, audit handoff bundling |

---

## Product non-negotiables

These are enforced by `scripts/policy-check.mjs`. A PR that violates any of
them will fail CI:

- The server never stores plaintext message bodies
- No cloud backup exists
- No account recovery, password reset, or admin override
- Identity is device-bound; transfer requires the old device alive
- Push payloads carry no plaintext or envelope fields
- `VEIL_ENV=production` refuses to boot until `VEIL_AUDITED_CRYPTO_ATTESTED=true`,
  which is set only after external cryptographic review completes

---

## Three deploy paths

```text
┌─────────────────────┬─────────────────────────────────────────────┐
│ Local LAN           │  pnpm demo:up                               │
│ (laptop + phone)    │  http://<laptop-LAN-IP>:3000/demo/          │
├─────────────────────┼─────────────────────────────────────────────┤
│ Public over Tunnel  │  pnpm demo:tunnel:up                        │
│ (laptop + Cloudflare│  Browse a real https://… URL anywhere       │
│  Zero Trust token)  │  See docs/cloudflare-tunnel-deploy.md       │
├─────────────────────┼─────────────────────────────────────────────┤
│ Production VPS      │  pnpm demo:prod:up                          │
│ (Hetzner / DO,      │  Caddy + TLS + Prometheus + Grafana         │
│  ~$5/month)         │  See docs/vps-deploy-runbook.md             │
└─────────────────────┴─────────────────────────────────────────────┘
```

---

## Current implementation status

### Cryptography
- Mobile: full Double Ratchet (DH ratchet + symmetric chain) on
  X25519 ECDH + HKDF-SHA256 + AES-256-GCM, plus Ed25519 device
  signing. Session state persisted in OS-level encrypted secure
  storage. Implementation in `apps/mobile/lib/src/core/crypto/`.
- Web demo: simpler per-message ECDH (envelope v2). Unified envelope
  v3 spec written ([`docs/envelope-v3-unified-spec.md`](docs/envelope-v3-unified-spec.md))
  but implementation deferred to post-audit.
- Group chats use a shared conversation key today. Sender Keys design
  in [`docs/group-sender-keys-design.md`](docs/group-sender-keys-design.md).
- Sealed Sender (metadata reduction) design in
  [`docs/sealed-sender-design.md`](docs/sealed-sender-design.md).

### Backend (`apps/api`)
- 19 modules: `auth`, `users`, `devices`, `conversations`, `messages`,
  `attachments`, `realtime`, `device-transfer`, `safety`, `metrics`,
  `push`, `calls`, `stories`, `groups`, `channels`, `contacts`,
  `profile`, `account`, `health`
- JWT with 1-hour TTL, atomic refresh (Redis `GETDEL`), JTI blacklist,
  WS force-disconnect on logout
- Custom `CfThrottlerGuard` prefers `cf-connecting-ip`, falls back to
  authenticated `deviceId`, then `x-forwarded-for`
- Atomic device transfer: serializable transaction creates new device
  and revokes old in one shot, then disconnects the old WS
- Reply / edit / delete on messages, with real-time `message.edited`
  and `message.deleted` events
- Reactions with `message.reaction` real-time fanout
- Bearer-token-gated `/v1/metrics` (Prometheus format)

### Web demo (`apps/web-demo`)
- Full message UI: reactions (long-press / right-click), reply, edit,
  delete, voice messages (push-to-talk MediaRecorder, opus, 30s cap)
- IndexedDB-backed session and message cache, encrypted at rest
- `i18n/{ko,en,ja}.json` with `?lang=` switcher
- PWA manifest + iconography
- Themed confirm dialogs replacing native `confirm()`

### Mobile (`apps/mobile`)
- Riverpod state, GoRouter navigation, Drift cache
- Full ratchet with session persistence
- Voice messages, reactions, reply scaffolding
- 401 → refresh interceptor on the API client
- Release builds fail loud when `keystore.properties` is missing
- iOS deployment target 14.0, R8 proguard rules, removed cydia probe

### Operations
- `pnpm demo:status` host + container health probe
- pg_dump cron snippet (daily, 14-day retention) in tunnel runbook
- [`docs/ops/abuse-triage.md`](docs/ops/abuse-triage.md) operator runbook
- [`docs/tester-guide-ko.md`](docs/tester-guide-ko.md) tester FAQ
- [`docs/ops/data-subject-request.md`](docs/ops/data-subject-request.md)
  GDPR/PIPA process

### Audit handoff
- `pnpm audit:handoff` bundles every doc + artifact + commit-pinned
  README into a single tarball for an external auditor
- Outreach templates: [`docs/audit-rfp-email-en.md`](docs/audit-rfp-email-en.md),
  [`docs/otf-application-template.md`](docs/otf-application-template.md)
- Firm shortlist: [`docs/external-audit-firm-shortlist.md`](docs/external-audit-firm-shortlist.md)

---

## Local development

1. Node `22.20.0` (see `.nvmrc`).
2. `cp .env.example .env` and `cp apps/api/.env.example apps/api/.env`.
3. `pnpm install`.
4. `pnpm docker:up` (Postgres + Redis + MinIO).
5. `pnpm db:generate`.
6. `pnpm dev:api`.
7. Web demo at `http://localhost:3000/demo/`.
8. For mobile: install Flutter, then `pnpm dev:mobile:api` (Android emu)
   or `pnpm dev:mobile:desktop` (Windows desktop sanity).

For Windows desktop builds enable Developer Mode so Flutter plugins can
create symlinks.

Mobile `--dart-define` runtime flags:
- `VEIL_API_BASE_URL` — default `http://localhost:3000/v1`. Use
  `http://10.0.2.2:3000/v1` for Android emulators.
- `VEIL_REALTIME_URL` — default `http://localhost:3000`.

---

## Useful scripts

### Daily
- `pnpm dev:api` — API dev server
- `pnpm test`, `pnpm lint`, `pnpm format:check`
- `pnpm -C apps/api test:e2e`

### Demo / Tunnel
- `pnpm demo:up` / `demo:logs` / `demo:down` / `demo:reset`
- `pnpm demo:tunnel:up` / `demo:tunnel:logs` / `demo:tunnel:down`
- `pnpm demo:status` — host + container health probe

### Production VPS
- `pnpm demo:prod:up` — full stack with Caddy TLS
- `pnpm demo:prod:obs` — add Prometheus + Grafana
- `pnpm demo:prod:logs` / `demo:prod:down`

### Beta + audit gates
- `pnpm beta:release:check`
- `pnpm beta:release:evidence`
- `pnpm beta:deploy:preflight -- --env-file apps/api/.env`
- `pnpm beta:external:bundle`
- `pnpm audit:handoff` — bundle + tarball for external auditor
- `pnpm beta:production:blockers`
- `node scripts/policy-check.mjs`

### Mobile
- `pnpm mobile:codegen` / `mobile:analyze` / `mobile:test`

### CI
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `pnpm ci:api`
and `pnpm ci:mobile` on every push and PR. The runtime smoke job runs
deploy preflight against the CI beta fixture and uploads release
evidence as workflow artifacts.

---

## ⚠️ Pre-audit warning

The production crypto adapter is wired and pinned by tests, but
**has not been externally audited**. Do not ship this code to a
public audience until independent cryptographic review completes
and findings are remediated. The API refuses to boot in
`VEIL_ENV=production` until `VEIL_AUDITED_CRYPTO_ATTESTED=true` is
set explicitly; that flag is an attestation, not a development
escape hatch.

For vulnerability reports see [`SECURITY.md`](SECURITY.md).

---

## Documentation index

### Start here
- [Architecture](docs/architecture.md)
- [Threat Model](docs/threat-model.md)
- [No Recovery rationale](docs/no-recovery.md)
- [Trusted Device Graph](docs/trusted-device-graph.md)

### Protocol flows
- [Message Flow](docs/message-flow.md)
- [Attachment Flow](docs/attachment-flow.md)
- [Device Transfer Flow](docs/device-transfer-flow.md)
- [Local Search and History Navigation](docs/local-search-history-navigation.md)

### Crypto specs
- [Crypto Envelope Spec](docs/crypto-envelope-spec.md) — current wire format
- [Forward Secrecy Ratchet Design](docs/forward-secrecy-ratchet-design.md) — implemented mobile ratchet
- [Envelope v3 Unified Spec](docs/envelope-v3-unified-spec.md) — design only, not implemented
- [Group Sender Keys Design](docs/group-sender-keys-design.md) — design only
- [Sealed Sender Design](docs/sealed-sender-design.md) — design only
- [Crypto Adapter Architecture](docs/crypto-adapter-architecture.md)
- [Crypto Mobile Bridge Design](docs/crypto-mobile-bridge-design.md)
- [Crypto Session State Migration](docs/crypto-session-state-migration.md)
- [Crypto Interoperability Fixtures](docs/crypto-interoperability-fixtures.md)
- [Audited Crypto Adapter Execution Plan](docs/audited-crypto-adapter-execution.md)
- [Audited Crypto Library Decision](docs/audited-crypto-library-decision.md)
- [Mock Crypto Replacement Plan](docs/mock-crypto-replacement.md)

### Deploy runbooks
- [MVP Demo Runbook](docs/mvp-demo-runbook.md)
- [Cloudflare Tunnel Deploy](docs/cloudflare-tunnel-deploy.md) — laptop + Cloudflare
- [VPS Deploy Runbook](docs/vps-deploy-runbook.md) — public-beta-ready VPS
- [Production Deployment Checklist](docs/production-deployment.md)
- [Internal Alpha Deployment / Runbook / Test Checklist / Desktop QA](docs/internal-alpha-runbook.md)
- [Launch Runbook](docs/launch-runbook.md)
- [Staging Push Enable Runbook](docs/staging-push-enable-runbook.md)

### Operations
- [Abuse Triage Runbook](docs/ops/abuse-triage.md)
- [Data Subject Request Process](docs/ops/data-subject-request.md)
- [JWT Secret Rotation](docs/ops/jwt-secret-rotation.md)
- [Tester Guide (Korean)](docs/tester-guide-ko.md)
- [Phone Access Walkthrough](docs/phone-access.md)
- [Push Privacy Review Checklist](docs/push-privacy-review-checklist.md)
- [Apple + Firebase Credential Setup](docs/apple-firebase-credential-setup-checklist.md)

### External audit
- [External Security Review Packet](docs/external-security-review-packet.md)
- [External Security Review Request Template](docs/external-security-review-request-template.md)
- [External Audit Firm Shortlist](docs/external-audit-firm-shortlist.md)
- [Audit RFP Email Template (English)](docs/audit-rfp-email-en.md)
- [OTF Application Template](docs/otf-application-template.md)
- [External Review Intake / Master Checklist / Remediation Tracker](docs/external-review-remediation-tracker.md)

### Status reports
- [Final Technical Status](docs/final-technical-status.md)
- [Private Beta Audit](docs/private-beta-audit.md)
- [Private Beta Readiness Report](docs/private-beta-readiness-report.md)
- [Private Beta Performance Profile](docs/private-beta-performance-profile.md)
- [Real-Device Performance Execution / Results / Triage](docs/real-device-performance-execution.md)
- [Telegram-Grade Private Beta Gap Analysis](docs/telegram-grade-private-beta-gap-analysis.md)
- [Six-Month Roadmap](docs/six-month-roadmap.md)

### Privacy + design
- [Privacy Policy — English](docs/privacy-policy-en.md)
- [Privacy Policy — Korean](docs/privacy-policy-ko.md)
- [Mobile Design System](docs/mobile-design-system.md)
- [Mobile Device Security](docs/mobile-device-security.md)
- [Observability Hygiene](docs/observability-hygiene.md)
- [Open Chat Design (draft)](docs/open-chat-design.md)
