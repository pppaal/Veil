# VEIL Private Beta Readiness Report

## Summary

VEIL is now prepared for a serious private-beta release process, not a public production launch.

The current repository is suitable for:

- private-beta engineering validation
- manual QA on real devices
- CI-gated release candidates
- external security review preparation

The current repository is not suitable for:

- public production launch
- audited cryptographic claims
- recovery-capable user support flows

## What is ready

### Engineering quality

- root verification scripts exist for API and mobile
- CI runs API/package verification, mobile codegen/analyze/test, and API container build
- alpha smoke is scripted
- Node version is pinned in [`.nvmrc`](c:/Users/pjyrh/OneDrive/Desktop/Veil/.nvmrc)

### Messaging and lifecycle

- register -> challenge -> verify is covered
- direct conversation creation is covered
- send/list/read and receipt flows are covered
- duplicate send and reconnect/backfill paths are covered
- attachment ticket, upload completion, and download ticket flows are covered
- app lock, local wipe, revoke, transfer success, and transfer failure are covered
- conversation session bootstrap metadata is persisted with versioned local and
  remote device binding for future audited crypto migration

### Privacy posture

- backend logs are structured and redacted
- push hints remain metadata-only
- policy checks block obvious plaintext-prone regressions
- mobile runtime blocks insecure remote HTTP/WS endpoints outside local development

## Test coverage posture

Automated coverage now includes:

- API unit tests
- API e2e tests
- mobile service/controller tests
- mobile widget/basic flow tests
- policy checks for privacy-sensitive guardrails

## Release-process posture

The release gate is now documented in:

- [Private Beta Release Process](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-release-process.md)
- [Private Beta Performance Profile](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-performance-profile.md)
- [External Security Review Packet](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [Observability Hygiene](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/observability-hygiene.md)
- [Internal Alpha Test Checklist](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/internal-alpha-test-checklist.md)
- `pnpm beta:release:evidence` writes a machine-readable handoff file to `artifacts/private-beta-release-evidence.json`

## Security assumptions

These assumptions remain explicit:

- the server stores ciphertext-like payloads only
- no recovery path exists
- no password reset exists
- transfer requires the old device
- private keys and equivalent local device material stay on-device
- mock crypto is still a placeholder seam and not a production security claim
- persisted session bootstrap metadata is versioned, but it is still only a
  migration-ready mock boundary and not real session cryptography

## Remaining risks

1. Mock crypto is still active and blocks production release.
2. Crash reporting is intentionally absent; if added later, it requires privacy review.
3. Push-provider integrations are still seams and need separate privacy review.
4. The local encrypted cache is private-beta hardening, not an audited secure mobile database design.
5. Real iOS/Android signing and store-distribution hardening remain release-engineering work outside this code pass.
6. Local message search is intentionally cache-backed and size-capped on-device, not a full encrypted archive engine.
7. Session bootstrap persistence is migration-ready, but real audited
   per-peer session state and migration logic are still future work.

## Release recommendation

Recommendation: `Private beta ready with explicit non-production cryptography caveat`.

Do not remove the production boot guard or claim production cryptographic security until the mock crypto replacement plan is complete.
