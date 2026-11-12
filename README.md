# VEIL

**Open-source, end-to-end encrypted messenger** — no phone number, no
email, no plaintext messages on the server.

[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![End-to-end encrypted](https://img.shields.io/badge/encryption-E2E%20X25519%20%2B%20AES--256--GCM-success.svg)](#cryptography)
[![Privacy invariants: CI-enforced](https://img.shields.io/badge/privacy%20invariants-CI--enforced-orange.svg)](scripts/policy-check.mjs)

> **No backup. No recovery. No leaks.**

Because the code is open source under the AGPL, the privacy claims below
are not "trust us" — anyone can read the source, run it, and verify them.

The design premise is the inverse of mainstream messengers: there is no
backup path, no password reset, no admin override, and no plaintext
messages on the server. Lose the device or wipe the browser, and the
conversation is gone for good. That tradeoff is the product.

The "no recovery" rule is not just documentation — it is encoded in
[`scripts/policy-check.mjs`](scripts/policy-check.mjs) as a CI gate that
fails the build on any commit that introduces a recovery flow or table, an
admin message viewer, plaintext in push payloads, wildcard CORS, or ad-hoc
console logging in mobile.

Three more gates keep the rest of this README honest:

- [`scripts/schema-privacy-check.mjs`](scripts/schema-privacy-check.mjs)
  requires a privacy annotation on every database field and publishes the
  result as [What a seized VEIL server reveals](docs/server-data-inventory.md).
- [`scripts/claims-check.mjs`](scripts/claims-check.mjs) fails CI when a
  privacy or security claim in this README, the privacy policies, the site
  or the store listings is not in the [claims ledger](docs/claims.yaml) with
  the test or gate that backs it.
- [`scripts/store-label-check.mjs`](scripts/store-label-check.mjs) fails CI
  when the App Store and Google Play privacy answers
  ([`store/appstore/app-privacy-answers.md`](store/appstore/app-privacy-answers.md),
  [`store/play/data-safety-answers.md`](store/play/data-safety-answers.md))
  leave out data the database stores, disagree with each other, or are
  contradicted by any other document.

---

## What this repo contains

| Path | Description |
|---|---|
| `apps/api/` | NestJS backend — 23 modules, Jest unit + supertest e2e suites, 18 Prisma migrations |
| `apps/mobile/` | Flutter app (iOS + Android) with full Signal-style double ratchet (`LibCryptoAdapter`), 32 test files |
| `apps/web-demo/` | Vanilla-JS web client — voice/image/file messages, reactions, reply/edit/delete, forward, search, @mentions, KakaoTalk import, block/mute. 47 Vitest unit + 4 Playwright e2e specs |
| `packages/contracts/` | Typed API + realtime contracts (single source of truth) |
| `packages/shared/` | Shared envelope versions and protocol constants |
| `infra/caddy/` | Production TLS reverse proxy |
| `infra/prometheus/` `grafana/` | Metrics + alerting + 8-panel dashboard, all auto-provisioned |
| `infra/docker/` | Demo / alpha / production Compose stacks |
| `docs/` | 60+ documents — architecture, threat model, runbooks, crypto specs, audit handoff, pre-audit review |
| `scripts/` | CI gates, release evidence, audit handoff bundling |

---

## Product non-negotiables

CI guards these with `scripts/policy-check.mjs`,
`scripts/schema-privacy-check.mjs` and the API tests; a PR that trips one of
those checks fails the build:

- The server stores no plaintext message content: messages, reactions and
  stories are ciphertext, and display names, profile text and contact names
  are not stored. Group and channel names and descriptions and device labels
  are still stored in readable form until their encryption ships. They are
  the only entries on the allowlist of `scripts/schema-privacy-check.mjs`,
  which fails CI when any other field named like user-written text (body,
  caption, bio, name, note and the like) is not ciphertext
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
│ Invited testers     │  pnpm demo:tunnel:up                        │
│ (laptop + Cloudflare│  https://… URL for testers you invite       │
│  Zero Trust token)  │  See docs/cloudflare-tunnel-deploy.md       │
├─────────────────────┼─────────────────────────────────────────────┤
│ Production VPS      │  pnpm demo:prod:up (boots only after the    │
│ (Hetzner / DO,      │  external crypto audit is attested)         │
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
- Web demo: a browser client for the same API; its protocol status is
  tracked in [`docs/envelope-v3-unified-spec.md`](docs/envelope-v3-unified-spec.md).
- Group chats: new mobile groups use **Sender Keys** (per-member HKDF
  chains, per-epoch Ed25519 authorship, full re-key on every join/leave;
  `veil-group-v1`). Groups created by older clients stay on the legacy
  shared conversation key. Design + implementation notes in
  [`docs/group-sender-keys-design.md`](docs/group-sender-keys-design.md).
- **libsignal bridge** (`--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`):
  the Dart adapter and the Kotlin/Swift handlers are in the tree, but default
  builds leave out the native bridge and the libsignal dependency and use the
  Dart ratchet. Opting in takes `-Pveil.libsignal=true` (Gradle) or
  `--android-project-arg=veil.libsignal=true` (Flutter) on Android; on iOS,
  adding `Runner/Crypto/VeilCryptoBridge.swift` and the `LibSignalClient`
  package to the Runner target and registering `VeilCryptoBridgePlugin` in
  `AppDelegate.swift`. Neither bridge has ever been built into an app. See
  [`docs/libsignal-migration-implementation.md`](docs/libsignal-migration-implementation.md).
- Sealed sender is under revision: the current design in
  [`docs/sealed-sender-design.md`](docs/sealed-sender-design.md) does not
  hide the sender from the server.

### Backend (`apps/api`)
- 23 modules: `auth`, `users`, `devices`, `conversations`, `messages`,
  `attachments`, `realtime`, `device-transfer`, `safety`, `metrics`,
  `push`, `calls`, `stories`, `groups`, `channels`, `contacts`,
  `profile`, `account`, `handles`, `prekeys`, `retention`, `secret`,
  `health`
- JWT with 1-hour TTL, atomic refresh (Redis `GETDEL`), JTI blacklist,
  WS force-disconnect on logout
- Custom `CfThrottlerGuard` prefers `cf-connecting-ip`, falls back to
  authenticated `deviceId`, then `x-forwarded-for`
- Atomic device transfer: serializable transaction creates new device
  and revokes old in one shot, then disconnects the old WS
- Reply / edit / delete on messages, with real-time `message.edited`
  and `message.deleted` events
- Reactions are ordinary encrypted messages (`messageType: 'reaction'`);
  the relay never sees the emoji or its target
- Stories are ciphertext addressed to an explicit audience of mutual
  contacts
- Deleted accounts' handles are quarantined for 90 days (only a peppered
  HMAC is kept), so nobody can re-register a contact's handle right away
- Device last-seen and last-sync times are kept to the UTC day
- Bearer-token-gated `/v1/metrics` (Prometheus format)

### Web demo (`apps/web-demo`)
- Full message UI: reactions (long-press / right-click), reply, edit,
  delete, forward, voice messages (push-to-talk MediaRecorder, opus,
  30s cap), image attachments (drag-drop + preview confirm + zoom),
  generic file attachments (PDF/video/zip, 25MB), in-conversation
  search, @mention autocomplete, 5-minute delete-undo
- Markdown lite in messages: `*bold*`, `_italic_`, `` `code` ``,
  ```` ```fenced code blocks``` ````, auto-linked URLs, @mention chips
- **KakaoTalk import**: drop a `.txt` export → read-only archive,
  parsed 100% in-browser, bytes never reach the server
- Block / mute / report UI wired to the safety endpoints
- Unified settings dialog: dark/light theme, language, sounds,
  notifications
- Browser notifications + tab unread badge, keyboard shortcuts
  (Ctrl/Cmd+K/N/F/+/), Web Audio send/receive tones (opt-in)
- IndexedDB-backed session + message cache (encrypted at rest);
  blob URLs revoked on delete/logout to bound memory
- `i18n/{ko,en,ja}.json` with `?lang=` switcher, locale-aware time
- PWA manifest + iconography, CSP meta, themed dialogs
- Testable helpers extracted to `lib/{markdown,format,kakao-import}.js`

### Mobile (`apps/mobile`)
- Riverpod state, GoRouter navigation, Drift cache
- Full ratchet with session persistence
- Voice messages, reactions, reply scaffolding
- 401 → refresh interceptor on the API client
- Release builds fail loud when `keystore.properties` is missing
- iOS deployment target 14.0, R8 proguard rules, removed cydia probe

### Operations
- `pnpm demo:status` host + container health probe
- No database dumps anywhere in the deployment (`no-database-dumps` policy rule; [runbook §6](docs/vps-deploy-runbook.md))
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
- `VEIL_TLS_PINS` — comma-separated TLS pins (`spki:<b64>` or `leaf:<b64>`)
  for the API and the realtime socket. Empty means no pinning; a release
  build refuses to run without it.
- `VEIL_OBJECT_STORAGE_HOSTS` — comma-separated hosts that presigned upload
  URLs may point at; an upload ticket naming another host is refused.
- `VEIL_OBJECT_STORAGE_PINS` — TLS pins for the object store, same format as
  `VEIL_TLS_PINS`; empty falls back to the platform trust store.

A release build refuses to run with a local relay URL or without
`VEIL_TLS_PINS`. The app has no `VEIL_ENV` define and ignores one.

---

## Useful scripts

### Daily
- `pnpm dev:api` — API dev server
- `pnpm test` — all unit suites (API Jest + web demo Vitest)
- `pnpm lint`, `pnpm format:check`
- `pnpm -C apps/api test:e2e` — API e2e (supertest)
- `pnpm -C apps/web-demo test` — web demo Vitest (markdown / format / kakao-import)
- `pnpm e2e:web` — Playwright browser e2e (needs a running demo stack;
  `pnpm e2e:web:install` once for chromium, `pnpm e2e:web:ui` to debug)

### Demo / Tunnel
- `pnpm demo:up` / `demo:logs` / `demo:down` / `demo:reset`
- `pnpm demo:tunnel:up` / `demo:tunnel:logs` / `demo:tunnel:down`
- `pnpm demo:status` — host + container health probe

### Production VPS (boots only after the external audit is attested)
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
- [사용 설명서 (Korean all-in-one guide)](docs/사용설명서.md) — 한 문서로 보는 VEIL
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
- [Internal Pre-Audit Crypto Review](docs/internal-precheck-crypto-review.md) — reading-level review, NOT external audit
- [Envelope v3 Unified Spec](docs/envelope-v3-unified-spec.md) — design only, not implemented
- [Group Sender Keys Design](docs/group-sender-keys-design.md) — design only
- [Sealed Sender Design](docs/sealed-sender-design.md) — under revision: the current design does not hide the sender
- [Crypto Adapter Architecture](docs/crypto-adapter-architecture.md)
- [Crypto Mobile Bridge Design](docs/crypto-mobile-bridge-design.md)
- [Crypto Session State Migration](docs/crypto-session-state-migration.md)
- [Crypto Interoperability Fixtures](docs/crypto-interoperability-fixtures.md)
- [Audited Crypto Adapter Execution Plan](docs/audited-crypto-adapter-execution.md)
- [Audited Crypto Library Decision](docs/audited-crypto-library-decision.md)
- [Mock Crypto Replacement Status](docs/mock-crypto-replacement.md) — replacement complete; mock adapter is test-only

### Deploy runbooks
- [MVP Demo Runbook](docs/mvp-demo-runbook.md)
- [Cloudflare Tunnel Deploy](docs/cloudflare-tunnel-deploy.md) — laptop + Cloudflare, invited testers only before the audit
- [VPS Deploy Runbook](docs/vps-deploy-runbook.md) — production VPS; refuses to boot until the external audit is attested
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
- [What a seized VEIL server reveals](docs/server-data-inventory.md) — generated from the schema in CI
- [Claims ledger](docs/claims.yaml) — every public claim and the test or gate behind it
- [Server-side metadata retention](docs/metadata-retention.md)
- [Privacy Policy — English](docs/privacy-policy-en.md)
- [Privacy Policy — Korean](docs/privacy-policy-ko.md)
- [Mobile Design System](docs/mobile-design-system.md)
- [Mobile Device Security](docs/mobile-device-security.md)
- [Observability Hygiene](docs/observability-hygiene.md)
- [Open Chat Design (draft)](docs/open-chat-design.md)

---

## License

VEIL is free software licensed under the **GNU Affero General Public
License v3.0 only** (AGPL-3.0-only). See [`LICENSE`](LICENSE) for the full
text.

The AGPL's network clause (§13) is deliberate: if you run a modified VEIL
server as a network service, you must offer your users the modified source.
This keeps the privacy invariants — no plaintext messages on the server, no
recovery path, no admin override — from being silently stripped out of a
hosted fork.

Being open source under a recognized FOSS license is also what makes VEIL
eligible for a funded external cryptographic review through programs like
the [Open Technology Fund](https://www.opentech.fund/) — the review that
gates the public launch (see
[`docs/otf-application-template.md`](docs/otf-application-template.md)).
