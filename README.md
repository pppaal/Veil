# Veil

Veil is an open-source, end-to-end encrypted messenger for phones and the web; you sign up with a handle, not a phone number or email.
The server never has the plaintext of your messages or the keys to read them.
There is no backup, no account recovery, no password reset and no admin override, so a lost phone means a lost account.

The code is open source under the AGPL, so anyone can read it, run it and
check the claims below.

CI enforces the rule against recovery:
[`scripts/policy-check.mjs`](scripts/policy-check.mjs) fails the build on any
commit that adds a recovery flow or table, an admin message viewer,
plaintext in push payloads, wildcard CORS or ad hoc console logging in
mobile.

Four more gates keep the rest of this README honest:

- [`scripts/schema-privacy-check.mjs`](scripts/schema-privacy-check.mjs)
  requires a privacy annotation on every database field and publishes the
  result as [What a seized Veil server reveals](docs/server-data-inventory.md).
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
- [`scripts/doc-facts.mjs`](scripts/doc-facts.mjs) fails CI (through
  `pnpm scripts:test`) when a document contradicts the code: it names a
  retired crypto adapter id as the production one, repeats a statement the
  code makes false, hard-codes a test or migration count, or treats the
  production boot guard as temporary.

---

## What this repo contains

| Path | Description |
|---|---|
| `apps/api/` | NestJS backend: 23 modules, Jest unit and supertest e2e suites, Prisma migrations |
| `apps/mobile/` | Flutter app (iOS and Android): protocol v2 (X3DH and Double Ratchet, `LibCryptoAdapter`), Sender Keys groups, `flutter test` suite |
| `apps/web-demo/` | Vanilla-JS web client: voice, image and file messages, reactions, reply, edit and delete, forward, search, @mentions, KakaoTalk import, block and mute. Protocol v2 on WebCrypto. Vitest unit and Playwright browser suites |
| `packages/contracts/` | Typed API and realtime contracts (single source of truth) |
| `packages/shared/` | Shared envelope versions and protocol constants |
| `infra/caddy/` | Production TLS reverse proxy |
| `infra/prometheus/` `grafana/` | Metrics, alerting and an 8-panel dashboard, all auto-provisioned |
| `infra/docker/` | Demo, alpha and production Compose stacks |
| `docs/` | 60+ documents: architecture, threat model, runbooks, crypto specs, audit handoff, pre-audit review |
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
- An account lives on one device; moving it to a new device needs the old one
- Push notifications only wake the app: they carry no plaintext and nothing
  from the encrypted message
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
- Mobile: protocol v2. X3DH with signed and one-time prekeys
  authenticates both parties, then a full Double Ratchet (DH ratchet and
  symmetric chain) on X25519 ECDH, HKDF-SHA256 and AES-256-GCM, with
  Ed25519 identity keys and device signing. Session state is persisted in
  OS-level encrypted secure storage. Implementation in `apps/mobile/lib/src/core/crypto/`.
- Web demo: a WebCrypto port of the same protocol v2
  (`apps/web-demo/src/crypto/`), specified in
  [`docs/crypto-envelope-spec.md`](docs/crypto-envelope-spec.md) § Protocol v2.
  It reproduces every protocol-v2 known-answer vector
  (`apps/web-demo/__tests__/kat-v2.test.js`), and
  `apps/mobile/test/interop/web_mobile_interop_test.dart` has the two clients
  exchange real frames in both directions.
- Group chats: new mobile groups use **Sender Keys** (per-member HKDF
  chains, per-epoch Ed25519 authorship, full re-key on every join and leave;
  `veil-group-v1`). Groups created by older clients stay on the legacy
  shared conversation key. Design and implementation notes in
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
- Custom `CfThrottlerGuard` keys a signed-in request by its device ID;
  any other request is keyed by the client address read from the one
  source `VEIL_CLIENT_IP_SOURCE` names (`socket`, the default,
  `cf-connecting-ip` or `x-forwarded-for`), and no other header is consulted
- Atomic device transfer: a serializable transaction creates the new device
  and revokes the old one in one step, then disconnects the old WS
- Reply, edit and delete on messages, with real-time `message.edited`
  and `message.deleted` events
- Reactions are ordinary encrypted messages (`messageType: 'reaction'`);
  the server never sees the emoji or its target
- Stories are ciphertext addressed to an explicit audience of mutual
  contacts
- Deleted accounts' handles are quarantined for 90 days (only a peppered
  HMAC is kept), so nobody can re-register a contact's handle right away
- Device last-seen and last-sync times are kept to the UTC day
- Bearer-token-gated `/v1/metrics` (Prometheus format)

### Web demo (`apps/web-demo`)
- Full message UI: reactions (long-press or right-click), reply, edit,
  delete, forward, voice messages (push-to-talk MediaRecorder, opus,
  30s cap), image attachments (drag-drop, preview confirm, zoom),
  generic file attachments (PDF, video, zip, 25MB), in-conversation
  search, @mention autocomplete, 5-minute delete-undo
- Markdown lite in messages: `*bold*`, `_italic_`, `` `code` ``,
  ```` ```fenced code blocks``` ````, auto-linked URLs, @mention chips
- **KakaoTalk import**: drop a `.txt` export to get a read-only archive,
  parsed entirely in the browser; the bytes never reach the server
- Block, mute and report UI wired to the safety endpoints
- Unified settings dialog: dark or light theme, sounds, notifications
- Browser notifications and a tab unread badge, keyboard shortcuts
  (Ctrl/Cmd+K/N/F/+/), Web Audio send and receive tones (opt-in)
- IndexedDB-backed session and message cache (encrypted at rest);
  blob URLs revoked on delete and logout to bound memory
- `i18n/en.json` as the single string dictionary (English only)
- PWA manifest and icon, CSP meta, themed dialogs
- Testable helpers extracted to `lib/{markdown,format,kakao-import}.js`

### Mobile (`apps/mobile`)
- Riverpod state, GoRouter navigation, Drift cache
- Full ratchet with session persistence
- Text messages, photos and files in 1:1 and group conversations,
  reactions, disappearing timers, unread counts, on-device message search,
  safety numbers, device transfer
- Block, report and mute: from a chat's menu, a message's long-press sheet
  and a contact's sheet, with Settings > Privacy > Blocked accounts; a muted
  chat raises no notification on the phone
- Photos come from the system photo picker and are re-encoded on the
  phone at up to 1600 px, which drops their location and camera details;
  files up to 25 MB come from the system file picker and go as they are.
  Received photos show in the chat and open full screen; files open with a
  tap (in another app on Android, in Quick Look on iOS, in the in-app viewer
  when they are a JPEG, PNG or WebP) or save to the phone. On the
  Windows desktop build the plus offers Photos only and there is no Save,
  and a received file opens only if it is a photo: File, Save and opening a
  file in another app exist only on Android and iOS
  ([apps/mobile/README.md](apps/mobile/README.md)).
- The app has no calls, voice messages, stories, stickers or assistant
- English only, one design system:
  [docs/mobile-design-system.md](docs/mobile-design-system.md)
- Refresh on 401 in the API client
- Release builds fail loudly when `keystore.properties` is missing
- iOS deployment target 14.0, R8 proguard rules, removed cydia probe

### Operations
- `pnpm demo:status` host and container health probe
- No database dumps anywhere in the deployment (`no-database-dumps` policy rule; [runbook §6](docs/vps-deploy-runbook.md))
- [`docs/ops/abuse-triage.md`](docs/ops/abuse-triage.md) operator runbook
- [`docs/tester-guide-ko.md`](docs/tester-guide-ko.md) tester FAQ (Korean)
- [`docs/ops/data-subject-request.md`](docs/ops/data-subject-request.md)
  GDPR/PIPA process

### Audit handoff
- `pnpm audit:handoff` bundles every doc, artifact and the commit-pinned
  README into a single tarball for an external auditor
- Outreach templates: [`docs/audit-rfp-email-en.md`](docs/audit-rfp-email-en.md),
  [`docs/otf-application-template.md`](docs/otf-application-template.md)
- Firm shortlist: [`docs/external-audit-firm-shortlist.md`](docs/external-audit-firm-shortlist.md)

---

## Local development

1. Node `22.20.0` (see `.nvmrc`).
2. `cp .env.example .env` and `cp apps/api/.env.example apps/api/.env`.
3. `pnpm install`.
4. `pnpm docker:up` (Postgres, Redis and MinIO).
5. `pnpm db:generate`.
6. `pnpm dev:api`.
7. Web demo at `http://localhost:3000/demo/`.
8. For mobile: install Flutter, then `pnpm dev:mobile:api` (Android emulator)
   or `pnpm dev:mobile:desktop` (Windows desktop sanity).

For Windows desktop builds enable Developer Mode so Flutter plugins can
create symlinks.

Mobile `--dart-define` runtime flags:
- `VEIL_API_BASE_URL`: default `http://localhost:3000/v1`. Use
  `http://10.0.2.2:3000/v1` for Android emulators.
- `VEIL_REALTIME_URL`: default `http://localhost:3000`.
- `VEIL_TLS_PINS`: comma-separated TLS pins (`spki:<b64>` or `leaf:<b64>`)
  for the API and the realtime socket. Empty means no pinning; a release
  build refuses to run without it.
- `VEIL_OBJECT_STORAGE_HOSTS`: comma-separated hosts that presigned upload
  and download URLs may point at; when it is set, a ticket naming another
  host is refused (empty allows any host).
- `VEIL_OBJECT_STORAGE_PINS`: TLS pins for the object store, same format as
  `VEIL_TLS_PINS`; empty falls back to the platform trust store.

A release build refuses to run with a local server URL or without
`VEIL_TLS_PINS`. The app has no `VEIL_ENV` define and ignores one.

---

## Useful scripts

### Daily
- `pnpm dev:api`: API dev server
- `pnpm test`: all unit suites (API Jest and web demo Vitest)
- `pnpm lint`, `pnpm format:check`
- `pnpm -C apps/api test:e2e`: API e2e (supertest)
- `pnpm -C apps/web-demo test`: web demo Vitest (markdown, format, kakao-import)
- `pnpm e2e:web`: Playwright browser e2e (needs a running demo stack;
  `pnpm e2e:web:install` once for Chromium, `pnpm e2e:web:ui` to debug)

### Demo and tunnel
- `pnpm demo:up` / `demo:logs` / `demo:down` / `demo:reset`
- `pnpm demo:tunnel:up` / `demo:tunnel:logs` / `demo:tunnel:down`
- `pnpm demo:status`: host and container health probe

### Production VPS (boots only after the external audit is attested)
- `pnpm demo:prod:up`: full stack with Caddy TLS
- `pnpm demo:prod:obs`: add Prometheus and Grafana
- `pnpm demo:prod:logs` / `demo:prod:down`

### Beta and audit gates
- `pnpm beta:release:check`
- `pnpm beta:release:evidence`
- `pnpm beta:deploy:preflight -- --env-file apps/api/.env`
- `pnpm beta:external:bundle`
- `pnpm audit:handoff`: bundle and tarball for the external auditor
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

## Not yet audited

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
- [사용 설명서 (Korean all-in-one guide)](docs/사용설명서.md): 한 문서로 보는 Veil
- [Architecture](docs/architecture.md)
- [Threat model](docs/threat-model.md)
- [Why there is no recovery](docs/no-recovery.md)
- [Trusted devices](docs/trusted-device-graph.md)

### Protocol flows
- [Message flow](docs/message-flow.md)
- [Attachment flow](docs/attachment-flow.md)
- [Device transfer flow](docs/device-transfer-flow.md)
- [Local search and history navigation](docs/local-search-history-navigation.md)

### Crypto specs
- [Crypto envelope spec](docs/crypto-envelope-spec.md): current wire format
- [Forward secrecy ratchet design](docs/forward-secrecy-ratchet-design.md): implemented mobile ratchet
- [Internal pre-audit crypto review](docs/internal-precheck-crypto-review.md): reading-level review, not an external audit
- [Envelope v3 unified spec](docs/envelope-v3-unified-spec.md): superseded by protocol v2, never implemented
- [Group Sender Keys design](docs/group-sender-keys-design.md): implemented on mobile (new groups), pre-audit
- [Sealed sender design](docs/sealed-sender-design.md): under revision, the current design does not hide the sender
- [Crypto adapter architecture](docs/crypto-adapter-architecture.md)
- [Crypto mobile bridge design](docs/crypto-mobile-bridge-design.md)
- [Crypto session state migration](docs/crypto-session-state-migration.md)
- [Crypto interoperability fixtures](docs/crypto-interoperability-fixtures.md)
- [Audited crypto adapter execution plan](docs/audited-crypto-adapter-execution.md)
- [Audited crypto library decision](docs/audited-crypto-library-decision.md)
- [Mock crypto replacement status](docs/mock-crypto-replacement.md): replacement complete; the mock adapter is test-only

### Deploy runbooks
- [MVP demo runbook](docs/mvp-demo-runbook.md)
- [Cloudflare tunnel deploy](docs/cloudflare-tunnel-deploy.md): laptop and Cloudflare, invited testers only before the audit
- [VPS deploy runbook](docs/vps-deploy-runbook.md): production VPS; refuses to boot until the external audit is attested
- [Production deployment checklist](docs/production-deployment.md)
- [Internal alpha deployment, runbook, test checklist and desktop QA](docs/internal-alpha-runbook.md)
- [Launch runbook](docs/launch-runbook.md)
- [Staging push enable runbook](docs/staging-push-enable-runbook.md)

### Operations
- [Abuse triage runbook](docs/ops/abuse-triage.md)
- [Data subject request process](docs/ops/data-subject-request.md)
- [JWT secret rotation](docs/ops/jwt-secret-rotation.md)
- [Tester guide (Korean)](docs/tester-guide-ko.md)
- [Phone access walkthrough](docs/phone-access.md)
- [Push privacy review checklist](docs/push-privacy-review-checklist.md)
- [Apple and Firebase credential setup](docs/apple-firebase-credential-setup-checklist.md)

### External audit
- [External security review packet](docs/external-security-review-packet.md)
- [External security review request template](docs/external-security-review-request-template.md)
- [External audit firm shortlist](docs/external-audit-firm-shortlist.md)
- [Audit RFP email template (English)](docs/audit-rfp-email-en.md)
- [OTF application template](docs/otf-application-template.md)
- [External review intake, master checklist and remediation tracker](docs/external-review-remediation-tracker.md)

### Status reports
- [Final technical status](docs/final-technical-status.md)
- [Private beta audit](docs/private-beta-audit.md)
- [Private beta readiness report](docs/private-beta-readiness-report.md)
- [Private beta performance profile](docs/private-beta-performance-profile.md)
- [Real-device performance execution, results and triage](docs/real-device-performance-execution.md)
- [Telegram-grade private beta gap analysis](docs/telegram-grade-private-beta-gap-analysis.md)
- [Six-month roadmap](docs/six-month-roadmap.md)

### Privacy and design
- [What a seized Veil server reveals](docs/server-data-inventory.md): generated from the schema in CI
- [Claims ledger](docs/claims.yaml): every public claim and the test or gate behind it
- [Server-side metadata retention](docs/metadata-retention.md)
- [Privacy policy (English)](docs/privacy-policy-en.md)
- [Privacy policy (Korean)](docs/privacy-policy-ko.md)
- [Design system](docs/mobile-design-system.md)
- [Mobile device security](docs/mobile-device-security.md)
- [Observability hygiene](docs/observability-hygiene.md)
- [Open chat design (draft)](docs/open-chat-design.md)

---

## License

Veil is free software licensed under the **GNU Affero General Public
License v3.0 only** (AGPL-3.0-only). See [`LICENSE`](LICENSE) for the full
text.

We chose the AGPL for its network clause (§13): if you run a modified Veil
server as a network service, you must offer your users the modified source.
This keeps the privacy invariants (no plaintext messages on the server, no
recovery path, no admin override) from being silently stripped out of a
hosted fork.

Being open source under a recognized FOSS license also makes Veil eligible
for a funded external cryptographic review through programs like the
[Open Technology Fund](https://www.opentech.fund/), and that review gates
the public launch (see
[`docs/otf-application-template.md`](docs/otf-application-template.md)).
