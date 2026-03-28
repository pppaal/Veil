# VEIL Threat Model Summary

## In scope

- server compromise attempting to read stored message data
- accidental plaintext leakage through logs, analytics, or push payloads
- unauthorized message access through hidden admin tooling
- account takeover attempts through password recovery or reset flows
- unsafe device transfer that bypasses possession of the old device

## Defensive product choices

- only encrypted envelopes are stored server-side
- no password reset and no recovery channels exist
- device transfer requires explicit action from the active old device
- push payloads are metadata-only
- no contact sync reduces unnecessary address-book exposure
- single active device model simplifies trust and revocation in v1

## Deliberate exclusions

- the current mock crypto adapter is not a security control
- multi-device concurrent session complexity is intentionally deferred
- public groups and social surfaces are intentionally absent

## Operational rules

- never log plaintext content
- never include plaintext in analytics or monitoring payloads
- never add server-side decryption endpoints
- never store private keys on the server
- rate limit public-facing endpoints
- validate all request DTOs

## Residual risks in this MVP scaffold

- audited cryptography is not yet integrated
- attachment upload/download URLs are scaffolds, not hardened presigned-storage production code
- mobile local database encryption-at-rest is prepared conceptually but not finalized
- transport/session hardening still needs production infrastructure work
