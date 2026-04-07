# VEIL Private Beta Release Process

This process is for a serious private-beta release candidate, not a demo build.

## 1. Toolchain baseline

- Node: `22.20.0` from [`.nvmrc`](c:/Users/pjyrh/OneDrive/Desktop/Veil/.nvmrc)
- pnpm: `10.28.0`
- Flutter: stable channel used by CI

## 2. Environment separation

- Local development uses [`.env.example`](c:/Users/pjyrh/OneDrive/Desktop/Veil/.env.example).
- Containerized alpha/private-beta rehearsal uses [`apps/api/.env.alpha.example`](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/.env.alpha.example).
- `VEIL_ENV=production` must stay blocked while the mock crypto seam remains in place.

## 3. Pre-release verification gate

Run all of the following from the repo root:

```bash
pnpm ci:api
pnpm ci:mobile
pnpm alpha:smoke
pnpm beta:release:check
pnpm beta:release:evidence
pnpm beta:deploy:preflight -- --env-file apps/api/.env
```

Required outcomes:

- build passes
- lint passes
- policy checks pass
- package/api tests pass
- API e2e passes
- mobile codegen/analyze/test passes
- alpha smoke passes against a running stack
- the combined release gate passes
- release evidence JSON is generated under `artifacts/private-beta-release-evidence.json`
- deploy preflight passes and writes `artifacts/private-beta-deploy-preflight.json`

Notes:

- `apps/api/.env.alpha.example` is only a wiring example.
- Replace placeholder JWT and provider secrets in the actual env file before expecting preflight to pass.
- CI uses [`apps/api/.env.beta.ci.example`](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/api/.env.beta.ci.example)
  to prove that the deploy preflight and beta artifact generation still work with a
  non-placeholder private-beta fixture.

## 4. QA gate

Use these documents together:

- [Internal Alpha Runbook](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/internal-alpha-runbook.md)
- [Internal Alpha Desktop QA](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/internal-alpha-desktop-qa.md)
- [Internal Alpha Test Checklist](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/internal-alpha-test-checklist.md)

Required manual checks:

- onboarding and no-recovery copy
- register -> challenge -> verify
- direct conversation creation
- send/receive message
- attachment upload/download ticket flow
- app lock and privacy shield
- transfer success and transfer expiry failure
- revoke behavior on the old device
- reconnect, backfill, and pagination behavior

## 5. Observability gate

Before any private-beta build is distributed:

- review [Observability Hygiene](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/observability-hygiene.md)
- confirm no plaintext fields in logs or push hints
- confirm no crash SDK has been added
- confirm request IDs propagate in API responses

## 6. Release packaging gate

- Generate mobile code before packaging.
- Produce signed build artifacts only from a clean tree.
- Record the commit SHA, env file source, and smoke-test result alongside the build.
- Keep release notes explicit that mock crypto is still in place.
- Run `pnpm beta:release:evidence` and attach the generated JSON to the candidate build handoff.
- Android package identity is `io.veil.mobile`. Release signing should come from
  [`apps/mobile/android/keystore.properties.example`](c:/Users/pjyrh/OneDrive/Desktop/Veil/apps/mobile/android/keystore.properties.example),
  not the debug keystore, for any distributed private-beta build.
- iOS bundle identifier is `io.veil.mobile`. Automatic signing is acceptable for
  internal development, but distributed private-beta archives should be cut with the
  intended Apple team and signing profile.

## 7. Go / no-go criteria

`GO` for private beta requires:

- all automated checks green
- all manual checklist items green
- no open issue that weakens no-recovery, device binding, or ciphertext-only server assumptions
- documentation updated for the exact build being distributed

`NO-GO` if any of these are true:

- policy checks fail
- transfer/revoke/app lock regress
- logs or alerts expose sensitive fields
- docs overclaim production-grade cryptographic security

## 8. Explicit non-claims

Do not claim any of the following in private beta:

- audited production E2EE
- production-ready recovery safety
- external security review completion
- push-provider privacy review completion

## 9. Required handoff docs

- [External Security Review Packet](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [Private Beta Performance Profile](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-performance-profile.md)
