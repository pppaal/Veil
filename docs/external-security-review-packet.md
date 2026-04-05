# VEIL External Security Review Packet

This packet is the minimum handoff set for a serious external review of the VEIL private beta.

It does not claim production cryptographic safety.

## Scope statement

Review the current VEIL private beta as:

- a privacy-first mobile messenger
- a trusted-device graph product
- a ciphertext-only relay architecture
- a mock-crypto implementation with a strict adapter boundary

Do not treat the current build as audited production E2EE.

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
6. Release posture and known limits
   - [private-beta-audit.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-audit.md)
   - [private-beta-readiness-report.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-readiness-report.md)
   - [production-deployment.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/production-deployment.md)

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
- exact commit SHA under review
- environment mode used for the review build
- current mobile build artifact identifiers

## Explicit caveats

- Mock crypto is still active.
- Push providers remain metadata-only seams unless a separate privacy review is attached.
- Production boot remains blocked until the audited crypto replacement is complete.
