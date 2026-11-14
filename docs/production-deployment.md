# Production Deployment Checklist

VEIL is not production-ready yet. This checklist is the minimum path to get there without violating the product philosophy.

The current API intentionally blocks `VEIL_ENV=production` at startup because `VEIL_AUDITED_CRYPTO_ATTESTED` is required to be `true` and `VEIL_AUDIT_REPORT_SHA256` must name the signed audit report, and the production crypto adapter (`LibCryptoAdapter`, `lib-x3dh-x25519-aes256gcm-v4`) has not yet completed external audit + remediation. The adapter itself is wired by default — the gate is on the audit, not on the implementation.

## 1. Complete external crypto audit and attestation

- Hand off the external review packet (see `docs/external-security-review-packet.md`).
- Track findings in `docs/external-review-remediation-tracker.md`.
- Once findings are remediated, set `VEIL_AUDITED_CRYPTO_ATTESTED=true` and
  `VEIL_AUDIT_REPORT_SHA256=<sha256sum of the signed report>` (64 lowercase hex
  characters). Production refuses to boot unless both are set.
- Boolean variables accept only `true`/`false`, `1`/`0` or `yes`/`no` (any case,
  surrounding whitespace ignored). Any other value fails boot; in particular
  `VEIL_AUDITED_CRYPTO_ATTESTED=false` is false, not "a non-empty string".
- Keep cross-platform crypto interoperability tests green before rollout.
- Do not add server-side decryption helpers.

## Client IP source

The rate limiter keys authenticated requests by device. Unauthenticated
requests are keyed by client address, read from exactly one source chosen with
`VEIL_CLIENT_IP_SOURCE`. Pick the one that matches what sits directly in front
of the API; a header the edge does not overwrite is attacker-controlled.

| Deployment | `VEIL_CLIENT_IP_SOURCE` | Notes |
| --- | --- | --- |
| API reachable directly (local dev) | `socket` (default) | Forwarding headers are ignored. |
| Behind Caddy (`docker-compose.prod.yml`) | `x-forwarded-for` | Caddy drops `CF-Connecting-IP` and overwrites `X-Forwarded-For` with the real peer. `VEIL_TRUSTED_PROXY_HOPS` (default `1`) must equal the number of proxies in front of the API. |
| Cloudflare Tunnel straight to the API (`docker-compose.demo.yml --profile tunnel`) | `cf-connecting-ip` | Every request arrives from `cloudflared`, so the socket address is useless. The header is used only when it is a single well-formed IP. Never expose the API port directly in this mode: start the stack with `VEIL_API_BIND_ADDRESS=127.0.0.1` so the host port is loopback-only (cloudflared uses the compose network). |

`VEIL_TRUST_PROXY` was removed; a deployment that still sets it fails boot
with `VEIL_TRUST_PROXY was removed; set VEIL_CLIENT_IP_SOURCE`.

## Rate limiting

With `VEIL_REDIS_URL` set (required in production), rate-limit counters live in
Redis (Redis 7 or newer) and are shared by every API instance. If Redis becomes
unreachable the limiter logs one warning per outage and fails open rather than
taking the relay down.

Known limits, accepted for now:

- Authentication runs before the limiter so that authenticated traffic is
  counted per device. A request that fails authentication on a protected route
  is rejected before the limiter sees it, so those 401s are not rate-limited by
  the API; bound them at the edge if they become a load problem.
- Unauthenticated buckets use the full client address, so one IPv6 client that
  controls a /64 can spread requests across many buckets.

The HTTP limiter does not run for realtime (WebSocket) events, so the gateway
has its own: each device may send a burst of 30 events (typing, call signals),
refilled at 5 a second, shared by all its sockets. Closing the sockets does not
reset it: a device that reconnects continues from what it had spent, so a
connect, send, disconnect loop gets no more than one open socket would. A call
signal is relayed only while its call is ringing or active, and only if its
data is at most 64 KiB; a socket frame over 128 KiB closes the socket. The
budget is kept per API instance.

## UnifiedPush

With `VEIL_PUSH_PROVIDER=unifiedpush`, production requires
`VEIL_UNIFIEDPUSH_ALLOWED_HOSTS` (comma-separated distributor hosts;
subdomains of a listed host are allowed). Device endpoints must be `https`
without credentials and may not be private, loopback, link-local, unique-local,
CGNAT, multicast, unspecified, benchmarking, documentation or reserved IP
literals, including IPv4-mapped, NAT64 and 6to4 forms of such IPv4 addresses;
registration rejects anything else with `validation_failed`. At delivery time
every resolved address of the host is checked as well, redirects are never
followed, the response body is never read, and requests time out after 10
seconds.

## 2. Harden device auth

- Refresh tokens are stored only as SHA-256 hashes and rotate on every use;
  presenting an already rotated token revokes its whole family, and logout
  revokes every family of the device. Release note: the first deploy of this
  storage format invalidates every refresh token issued before it, and clients
  recover by signing a fresh challenge with their device key.
- Keep challenge verification on uploaded device auth public keys only.
- Add secure hardware or platform keystore integration where supported.
- Add explicit device-key lifecycle review for revoke, transfer, and local wipe.
- Keep device transfer dependent on old-device possession.
- Rotate and invalidate bearer tokens on revoke/transfer in production infrastructure.

## 3. Harden storage

- Move from local/dev object storage tickets to real presigned URL generation.
- Enforce strict bucket policies for encrypted blobs only.
- Add object retention, content-size controls, and abuse controls.
- Keep the mobile local cache encrypted at rest and review key lifecycle on logout/revoke.

## 4. Harden operations

- Move all secrets to a managed secret store.
- Use TLS everywhere.
- Isolate Postgres, Redis, and object storage in private networks.
- Add structured log sinks that never store plaintext message content.
- Review metrics and traces for accidental payload leakage.

## 5. Mobile release work

- Add iOS and Android signing configuration.
- Validate biometric and PIN flows on real devices.
- Run Drift codegen in CI for mobile builds.
- Add release QA for onboarding, chat, attachments, app lock, revoke, and transfer.

## 6. Delivery and infra

- Add environment-specific deploy manifests.
- Add migration automation for Prisma.
- Publish API images from CI.
- Add staged deployment with smoke checks against `/v1/health`.
- Keep the production boot guard. It is never removed: the attestation in section 1 (`VEIL_AUDITED_CRYPTO_ATTESTED=true` with `VEIL_AUDIT_REPORT_SHA256` naming the signed report) is what satisfies it.

## 7. Security review

- Conduct a formal threat model review against the implemented system.
- Run application and infrastructure penetration tests.
- Verify there is no plaintext in logs, analytics, push payloads, or storage.
- Verify there is no hidden recovery path, server-side decryption, or admin message viewer. The server-side recovery backup module was removed, and `pnpm policy:check` plus the route-auth matrix test fail on any recovery or backup route.
