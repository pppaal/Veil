# VEIL Private Beta Audit

## Current state summary

VEIL is now positioned as a technically hardened private beta, not a demo shell. The repository keeps the product philosophy intact:

- no backup
- no recovery
- no password reset
- device-bound identity
- old-device-required transfer
- ciphertext-like payloads only on the server
- no plaintext message content in backend logs or push payloads

The current codebase is suitable for private-beta engineering validation and external security review preparation, but it is not production-ready while the mock crypto boundary remains in place.

## Critical gaps identified

Before this hardening pass, the highest-risk gaps were:

1. API transport posture was too open:
   - no security headers
   - wildcard websocket CORS
   - no explicit origin allowlist
2. Mobile runtime accepted insecure remote HTTP and WS endpoints.
3. Local logout/revoke did not wipe device-bound sensitive material or encrypted cache state.
4. Encrypted-at-rest cache reads still accepted legacy plaintext values.
5. Documentation still described an internal-alpha posture more than a private-beta hardening posture.
6. Device auth challenges could overlap for a single device, leaving more than one active challenge window at a time.

## Patch order

1. Tighten API transport, headers, and origin controls.
2. Add mobile runtime transport validation for private beta.
3. Wipe sensitive local state on logout/revoke and fail closed on unencrypted cache payloads.
4. Expand policy checks and release docs so regressions are visible in CI and review.
5. Reduce auth challenge replay surface and tighten local search/history behavior under long-history UI races.
6. Re-run build, lint, backend tests, e2e, mobile analyze, and mobile tests.

## Implemented changes

### API hardening

- Added `helmet` security headers in bootstrap.
- Added explicit CORS allowlist support through `VEIL_ALLOWED_ORIGINS`.
- Added `VEIL_TRUST_PROXY` and `VEIL_ENABLE_SWAGGER` runtime controls.
- Restricted realtime origin handling to configured allowlisted origins instead of wildcard CORS.

### Mobile hardening

- Added runtime endpoint validation so non-local insecure HTTP or WS endpoints are rejected at startup.
- Updated splash flow to stop routing and show a blocking runtime-configuration error when transport policy is violated.
- Wiped session, device secrets, cache key, and cached conversation data on logout.
- Tightened local encrypted cache reads so unencrypted payloads are rejected instead of silently accepted.
- Limited auth challenge validity to the newest challenge issued for a device instead of allowing multiple simultaneous active challenges.
- Tightened local search paging so stale in-flight responses are discarded and repeated page-boundary matches are not rendered twice.

### Release-readiness and review support

- Updated environment examples to include origin, proxy, and Swagger controls.
- Updated README and deployment docs to reflect the private-beta hardening posture.
- Added CI policy coverage for security headers and forbidden wildcard realtime CORS.

## Remaining risks

These items still block true production release:

1. Mock crypto is still active.
2. Push provider integration is still a seam only.
3. Attachment blobs still preserve architecture but not audited cryptographic guarantees.
4. Device transfer UX remains functional but not yet a polished production QR/device-pairing experience.
5. Production boot remains intentionally blocked until audited crypto is integrated.
6. Local message search is still bounded to trusted-device cache state, not a full encrypted archive index.

## Exact next steps

1. Replace the mock mobile/shared crypto adapters with audited messaging/session primitives behind the current `CryptoEngine` boundary.
2. Add cross-platform crypto interoperability tests and external security review artifacts.
3. Wire real APNs/FCM providers behind the current metadata-only push seam.
4. Prepare signed iOS/Android private-beta builds and execute the existing private-beta QA runbooks on real devices.
5. Keep `VEIL_ENV=production` blocked until the audited crypto replacement is complete.
