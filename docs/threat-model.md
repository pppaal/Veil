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
- push payloads are metadata-only (senderDeviceId excluded)
- no contact sync reduces unnecessary address-book exposure
- single active device model simplifies trust and revocation in v1
- rate limiting on auth, user lookup, and key bundle endpoints
- Helmet security headers (CSP, HSTS, COEP) in production
- Swagger disabled by default in production

## Deliberate exclusions

- the production crypto adapter has not yet been externally audited
- multi-device concurrent session complexity is intentionally deferred
- public social surfaces and open discovery are intentionally absent
- private group messaging is supported; public groups are not

## Operational rules

- never log plaintext content
- never include plaintext in analytics or monitoring payloads
- never add server-side decryption endpoints
- never store private keys on the server
- rate limit public-facing endpoints
- validate all request DTOs

## Residual risks

- production crypto adapter (X25519+AES-256-GCM) is integrated but not yet externally audited
- attachment upload/download URLs are scaffolds, not hardened presigned-storage production code
- mobile local database encryption-at-rest is prepared conceptually but not finalized
- transport/session hardening still needs production infrastructure work
