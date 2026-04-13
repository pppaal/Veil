# VEIL External Security Review Request Template

Last updated: 2026-04-08

Use this as the initial email or message to an external reviewer.

Related docs:

- [external-security-review-packet.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-security-review-packet.md)
- [external-review-remediation-tracker.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-review-remediation-tracker.md)
- [final-technical-status.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/final-technical-status.md)

## Subject

`Security Review Request: VEIL privacy-first mobile messenger private beta`

## Mail body

Hello,

We are requesting an external security review for VEIL, a privacy-first mobile
messenger currently in private beta preparation.

VEIL product rules are intentionally strict:

- no backup
- no recovery
- no password reset
- device-bound identity
- old-device-required device join and transfer
- server stores ciphertext-like payloads only
- no plaintext push payloads
- no admin message viewer or hidden decryption path

We are not requesting a generic feature review. We want a focused review of the
current architecture and implementation boundaries under those constraints.

## Requested scope

Please review the following areas:

- device registration, challenge, and verify flows
- trusted-device graph and revoke behavior
- old-device-required transfer flow
- local storage and app-lock boundaries
- messaging reliability and ciphertext-only relay assumptions
- attachment ticket and opaque blob flow
- metadata-only push assumptions
- logging and observability hygiene
- no-recovery/no-backup model consistency

## Important implementation note

The current crypto layer is still mock-backed for architecture and development
workflow reasons. We are not making a production cryptography claim yet.

We do want review of:

- the crypto abstraction boundary
- whether business logic is appropriately isolated from mock internals
- migration risks for audited real crypto integration

We do not want the mock layer to be mistaken for final production security.

## Requested outputs

Please provide:

- findings with severity
- concrete reproduction notes where possible
- architecture risks and trust-boundary concerns
- recommended remediation priorities
- explicit notes on any privacy leakage risks

## Review packet

We can provide:

- architecture and threat model documents
- release-readiness documents
- external execution status artifacts
- source repository access
- relevant test and CI outputs

## Desired timeline

Requested start:

- `<fill in desired start date>`

Requested review window:

- `<fill in expected review window>`

## Main contact

- Name: `<fill in>`
- Role: `<fill in>`
- Email / chat: `<fill in>`

Thank you.

## Internal hand-off note

After the reviewer responds:

1. capture the agreed scope
2. create a findings record from the reply
3. move findings into
   [external-review-remediation-tracker.md](c:/Users/pjyrh/OneDrive/Desktop/Veil/docs/external-review-remediation-tracker.md)
4. route implementation findings back into the repo for patching
