# VEIL External Security Review Packet

This packet is the minimum handoff set for a serious external review of the VEIL private beta.

It does not claim production cryptographic safety.

## Scope statement

Review the current VEIL private beta as:

- a privacy-first mobile messenger
- a trusted-device graph product
- a ciphertext-only relay architecture
- a production crypto implementation (X25519+AES-256-GCM) with a strict adapter boundary

Do not treat the current build as externally audited production E2EE until the external review is complete.

## Required packet contents

1. Product philosophy and non-negotiables
   - [no-recovery.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/no-recovery.md)
   - [trusted-device-graph.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/trusted-device-graph.md)
2. System and threat model
   - [architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/architecture.md)
   - [threat-model.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/threat-model.md)
3. Messaging, transfer, and attachment flows
   - [message-flow.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/message-flow.md)
   - [device-transfer-flow.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/device-transfer-flow.md)
   - [attachment-flow.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/attachment-flow.md)
4. Local security and observability posture
   - [mobile-device-security.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/mobile-device-security.md)
   - [observability-hygiene.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/observability-hygiene.md)
5. Crypto boundary and migration posture
   - [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md)
   - [mock-crypto-replacement.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/mock-crypto-replacement.md)
   - [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
6. Release posture and known limits
   - [private-beta-audit.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-audit.md)
   - [private-beta-readiness-report.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-readiness-report.md)
   - [production-deployment.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/production-deployment.md)
   - [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)

## Questions the review must answer

1. Does the current architecture preserve:
   - no backup
   - no recovery
   - device-bound identity
   - old-device-required join
   - ciphertext-only server handling
2. Are there any paths that could leak plaintext through:
   - logs
   - push payloads
   - temp files
   - local cache
   - admin/debug tooling
3. Are revoke, transfer expiry, and stale-device handling strong enough for private beta?
4. Is the crypto adapter boundary strict enough to support audited replacement without reworking product logic?

## Evidence to provide alongside docs

- latest green CI run
- latest `pnpm beta:release:check` result
- latest `artifacts/private-beta-release-evidence.json`
- latest `artifacts/external-security-review-manifest.json`
- latest `artifacts/external-review-findings-template.json`
- exact commit SHA under review
- environment mode used for the review build
- current mobile build artifact identifiers

## Findings handling

When findings arrive:

1. record them in
   [external-review-remediation-tracker.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-review-remediation-tracker.md)
2. patch the repo
3. re-run verification
4. attach retest evidence

## Machine-readable artifacts

- `pnpm beta:external:bundle` generates all handoff artifacts
- `pnpm beta:production:blockers` generates the production blockers report
- `artifacts/external-security-review-manifest.json`: review scope and file inventory
- `artifacts/external-review-findings-template.json`: structured findings template with severity and status fields
- `artifacts/private-beta-release-evidence.json`: CI and verification evidence
- `artifacts/production-blockers-report.json`: current production blocker summary

## Explicit caveats

- Production crypto adapter (LibCryptoAdapter) is integrated but not yet externally audited.
- Push providers remain metadata-only seams unless a separate privacy review is attached.
- Production boot remains blocked until external cryptographic audit is complete.
