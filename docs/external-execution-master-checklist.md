# VEIL External Execution Master Checklist

Last updated: 2026-04-17

This is the single entry point for the remaining work that cannot be completed
 purely inside the repository.

Use this document to coordinate:

- audited crypto selection and integration planning
- APNs/FCM credential onboarding and privacy review
- real-device performance profiling
- external security review

This checklist does not weaken VEIL philosophy.

Machine-readable status:

- `pnpm beta:external:status`
- `pnpm beta:external:bundle`
- output: `artifacts/external-execution-status.json`

## Overall release condition

VEIL remains:

- private-beta ready
- not public-production ready

Production remains blocked until all four tracks below are complete.

## Track 1. Audited crypto

Status:
- production adapter integrated (LibCryptoAdapter: X25519+AES-256-GCM+Ed25519)
- envelope version: `veil-envelope-v1`, algorithm hint: `x25519-aes256gcm`
- external audit still required

Primary doc:
- [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
- [audited-crypto-library-decision.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-library-decision.md)
- [crypto-adapter-architecture.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/crypto-adapter-architecture.md)

Required outputs:
- external cryptographic audit of LibCryptoAdapter
- interoperability fixture expansion
- cross-device verification tests

Go when:
- external audit is complete with no critical findings
- interoperability fixtures cover sender, receiver, attachment, and transfer
- no-recovery and device-bound rules remain intact

No-Go if:
- private keys would leave device-side storage
- cloud recovery semantics are introduced
- product logic outside the adapter boundary must be rewritten

## Track 2. Push credential onboarding and privacy review

Status:
- provider code path exists
- delivery remains intentionally disabled

Primary doc:
- [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)

Quick readiness check:
- `pnpm beta:push:readiness`

Required outputs:
- APNs credentials
- FCM credentials
- payload inspection evidence
- provider privacy sign-off
- staged enablement decision

Go when:
- metadata-only payload review is complete
- credentials are injected securely
- provider logs and alerts are reviewed

No-Go if:
- plaintext fields appear in payloads, logs, or dashboards
- provider enablement would bypass realtime or weaken relay semantics

## Track 3. Real-device performance profiling

Status:
- repo templates and execution docs are ready
- measurements still need to be captured on hardware

Primary docs:
- [real-device-performance-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-execution.md)
- [real-device-performance-results-template.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-results-template.md)

Required outputs:
- Android mid-range run
- Android flagship run
- recent iPhone run
- wide-layout run
- filled metrics and qualitative notes

Go when:
- conversation list, chat, search, and attachment flows stay responsive
- reconnect and resume are understandable and bounded
- no major larger-text or adaptive-layout regression remains

No-Go if:
- long-history scroll jank is persistent
- jump-to-context is unstable
- pending states or attachment retries confuse the user

## Track 4. External security review

Status:
- handoff packet prepared
- actual external review still required

Primary doc:
- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)

Required outputs:
- reviewer scope confirmation
- findings report
- remediation tracker
- remediation list
- retest or acceptance decision

Go when:
- review is complete
- critical findings are fixed
- production claims remain accurate

No-Go if:
- crypto path is unreviewed
- plaintext leakage concerns remain unresolved
- revoke/transfer/device trust findings remain open

## Recommended execution order

1. audited crypto library and bridge decision
2. push credential setup and privacy review
3. real-device profiling
4. external review handoff
5. remediation and retest
6. production go/no-go review

## Required artifacts before production decision

- green CI and release evidence
- green deploy preflight for target env
- green runtime smoke for target stack
- crypto decision artifacts
- push privacy review evidence
- real-device profiling results
- external review findings and remediation status

## Related docs

- [final-technical-status.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/final-technical-status.md)
- [private-beta-readiness-report.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-readiness-report.md)
- [private-beta-release-process.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/private-beta-release-process.md)
- [audited-crypto-adapter-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/audited-crypto-adapter-execution.md)
- [push-privacy-review-checklist.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/push-privacy-review-checklist.md)
- [real-device-performance-execution.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/real-device-performance-execution.md)
- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [external-review-remediation-tracker.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-review-remediation-tracker.md)
