# Deployment Readiness Review

_Reviewed at commit `29ca021` (branch `claude/deployment-readiness-review-fza1pf`)._

This is an engineering deployment-readiness assessment of the VEIL monorepo:
what is green, what gates production, and the smaller items worth cleaning up
before a public launch. It is **not** a security audit and does not replace the
external cryptographic review that the project itself requires.

## Verdict

VEIL is **not production-ready by design, and correctly so.** The single hard
blocker is the external cryptographic audit — the API refuses to boot with
`VEIL_ENV=production` until `VEIL_AUDITED_CRYPTO_ATTESTED=true`, and that flag
is meant to be flipped only after independent review of `LibCryptoAdapter`
clears and the remediation tracker is empty.

Setting that aside, the codebase is **engineering-mature and safe to run for
private beta today.** Every automated gate passes, the production boot path is
defensively validated, and the privacy invariants are enforced in CI rather
than asserted in prose. There is no evidence of the usual "not ready" smells
(failing tests, missing config validation, secrets in the repo, wildcard CORS,
plaintext logging).

## Evidence — gates run for this review

All commands below were run against a clean install of the repo and passed:

| Gate | Command | Result |
|---|---|---|
| Privacy policy invariants | `node scripts/policy-check.mjs` | ✅ passed |
| Crypto architecture boundary | `node scripts/crypto-architecture-check.mjs` | ✅ passed |
| Crypto KAT / test vectors | `node scripts/crypto-test-vectors.mjs --check` | ✅ passed |
| Build (shared + contracts + api) | `pnpm build` | ✅ exit 0 |
| Type/lint | `pnpm lint` | ✅ exit 0 |
| API unit tests | `pnpm -C apps/api test` | ✅ **276 passed / 30 suites** |
| Web-demo unit tests | `pnpm -C apps/web-demo test` | ✅ **47 passed / 4 files** |

Not run here (require Docker/Postgres or the Flutter SDK, but are wired in CI):
API e2e (`test:e2e`), web-demo Playwright e2e, mobile `ci:mobile`, and the
runtime smoke + deploy-preflight job.

## What is genuinely strong

**Boot-time production gate** (`apps/api/src/common/config/app-config.service.ts`,
`assertProductionReady`). Production refuses to start unless every one of these
holds — this is the standout piece of the deployment posture:
- crypto audit attested;
- `VEIL_ALLOWED_ORIGINS` has no `*`;
- `VEIL_JWT_SECRET` is ≥32 chars and not a placeholder (`replace-me`, `demo`,
  `changeme`, … are all rejected by regex);
- `VEIL_S3_PUBLIC_ENDPOINT` is not localhost;
- Swagger is off;
- push delivery, if enabled, has real APNs/FCM/UnifiedPush credentials;
- `VEIL_REDIS_URL` is set (the in-memory ephemeral store cannot enforce
  single-use refresh tokens or the JTI blacklist across processes).

**Env schema** validates all inputs at startup via zod (`env.schema.ts`),
including coercions and sane defaults; a bad env fails fast rather than at first
request.

**HTTP hardening** (`main.ts`): helmet with production CSP (`default-src 'none'`,
`frame-ancestors 'none'`), HSTS (2 y, preload), CORS via an allowlist callback,
body limit bounded to 512 kb, global `ValidationPipe` with
`forbidNonWhitelisted`, shutdown hooks enabled, Swagger only when explicitly on.

**Metrics endpoint** (`metrics.controller.ts`) is bearer-gated with a
constant-time compare, returns **404 (not 401)** when unconfigured so it does
not advertise the seam, and `no-store`. Metric labels deliberately exclude
identity fields to avoid metadata leakage over time.

**Rate limiting** (`cf-throttler.guard.ts`) fixed a real header-spoof hole:
`cf-connecting-ip` is only trusted when the operator opts in, otherwise it falls
back to authenticated `deviceId` — so a client can't mint a fresh throttle
bucket per request against the unauthenticated `/auth` and registration routes.

**Realtime gateway** rejects disallowed origins on connect and sets `cors: false`
(no wildcard).

**Container/infra**: multi-stage-ish Dockerfile with a `HEALTHCHECK` hitting
`/v1/health`; entrypoint runs `prisma migrate deploy` before starting; the prod
compose sets resource limits on every service, `restart: always`, healthchecks
+ `depends_on: service_healthy` for Postgres/Redis, private `expose` (no host
port publishing except Caddy 80/443), and `.env.prod`-sourced secrets with
`:?required` guards so a missing secret aborts `up`.

## Blocker (by design)

**External cryptographic audit is incomplete.** `docs/production-deployment.md`
and the boot gate both encode this. `LibCryptoAdapter` (`lib-x25519-aes256gcm-v3`)
is wired and pinned by tests but has not had independent review. This is the
intended gate; do not set `VEIL_AUDITED_CRYPTO_ATTESTED=true` to work around it.
Nothing in this review changes that recommendation.

## Non-blocking items worth cleaning up before launch

> Items 1–4 were **addressed in this branch**; 5–6 remain as tracked follow-ups.

1. **Stale counts in `README.md`.** ✅ _Fixed._ It stated "132 unit + 7 e2e
   tests / 10 migrations / 19 modules"; the tree actually has **276 API unit
   tests, 8 e2e, 16 migrations, 23 modules** (plus 32 mobile test files and 47
   web-demo Vitest tests). The README is the audit-handoff cover sheet, so it
   should track reality — counts corrected.

2. **`/v1/health/ready` field naming.** ✅ _Fixed._ The auth-gating (bearer
   token) is deliberate and left as-is — only the plain `/v1/health` (public) is
   used by container/load-balancer probes, and the Dockerfile healthcheck
   already uses the right one. The confusingly-named readiness field
   `productionBootBlocked: !isProduction` (which read `true` when _not_ in
   production) was renamed to `productionMode: isProduction`.

3. **Caddy started on `api: service_started`, not `service_healthy`.** ✅
   _Fixed._ Caddy could briefly route to an API still running
   `prisma migrate deploy`, returning 502s. The `depends_on` condition is now
   `service_healthy`, which waits on the API image's `HEALTHCHECK`.

4. **Backups were a runbook snippet, not automation.** ✅ _Fixed._ Added a
   first-class `postgres-backup` service to `docker-compose.prod.yml` — same
   `postgres:16-alpine` image as the DB (version-matched, no new supply-chain
   image), daily `pg_dump -F c` to the `veil_prod_backups` volume with
   `BACKUP_RETENTION_DAYS` pruning. Offsite copy (rclone → R2) remains a
   documented operator step, since an on-box volume alone doesn't survive host
   loss. The "no recovery" philosophy is about _message plaintext_; server
   Postgres (accounts, device graph, conversation metadata) still needs durable
   backups for continuity.

5. **No image publishing / single API replica.** CI builds the API image but
   doesn't push it to a registry; deploys build on the host via compose, and the
   stack runs one `api` container. That's fine for the ~$5 VPS beta target, but
   the Redis-required design implies eventual multi-instance — horizontal
   scaling (replicas + a shared session/LB story) is not yet wired. Fine to
   defer past beta.

6. **Push delivery is off (`VEIL_PUSH_PROVIDER=none`).** Expected for private
   beta; flagged only so it's a conscious pre-launch checklist item alongside
   the APNs/FCM credential + privacy-review work already tracked in
   `docs/production-blockers-report.json`.

## Bottom line

- **Private beta over TLS (VPS or Cloudflare Tunnel): ready now.** The gates are
  green and the boot-time guardrails are strong.
- **Public production: gated on the external crypto audit** — the project's own
  hard blocker — plus the small operational cleanups above (backups automation,
  README refresh, startup-ordering and readiness-endpoint polish).

None of the non-blocking items are correctness bugs; they are launch-hygiene
polish. The dominant remaining work is external review, exactly as the repo
already documents.
