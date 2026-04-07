# VEIL Six-Month Roadmap

Last updated: 2026-04-07

## Scoring baseline

### Private-beta score

- overall private-beta quality: `8.1 / 10`
- messaging reliability: `8.4 / 10`
- privacy/security architecture: `8.3 / 10`
- mobile UX/design polish: `8.0 / 10`
- release discipline: `8.2 / 10`

### Production-grade messenger score

- overall production-grade readiness: `5.6 / 10`

This gap exists mainly because of:

- mock-backed crypto
- real push-provider review still pending
- real-device performance evidence still pending
- external security review still pending

## 0 to 6 months

Goal: finish the transition from strong private beta to externally reviewable secure beta.

### Must finish

- audited real crypto adapter selection
- native bridge strategy for Flutter mobile crypto integration
- APNs/FCM credential onboarding
- privacy review for metadata-only push delivery
- real-device profiling on Android and iPhone
- external security review handoff and first findings triage

### Repo work that can proceed in parallel

- keep `CryptoEngine` boundary stable
- add interoperability fixtures for real crypto migration
- tighten local session-state storage assumptions
- preserve the new versioned session-bootstrap persistence contract across
  cache, controller, and fixture changes
- keep release evidence and deploy preflight green

### Exit criteria

- mock crypto replacement plan is implementation-ready
- push delivery path is review-ready
- profiling evidence exists for large history, search, media, and reconnect
- external review packet is complete

## 6 to 12 months

Goal: production-candidate hardening.

### Must finish

- audited crypto integration behind the current adapter boundary
- migration strategy for local session state
- true provider-backed push delivery with privacy review sign-off
- large-history performance fixes from real-device findings
- stronger media transport and cache tuning
- remediation of first external review findings

### Product quality target

- top-tier private messenger responsiveness
- stable long-history search and navigation
- resilient background wake-up and reconnect
- cleaner release signing and store-distribution process

### Exit criteria

- real crypto is active instead of the mock adapter
- external review findings are either fixed or formally accepted
- production boot guard can be reevaluated

## 12 to 18 months

Goal: mature production launch candidate without weakening VEIL philosophy.

### Must finish

- second-pass security review or targeted retest
- final operational hardening
- monitored staged rollout with privacy-safe observability
- production release playbooks for incident response, revoke flows, and beta migration

### Quality target

- Telegram-grade speed and navigation feel
- strong large-history behavior on real devices
- stable media reliability under adverse networks
- clear device-trust lifecycle UX

### Exit criteria

- release blockers are external-review clear
- production environment gating is intentionally lifted
- VEIL can honestly claim production readiness without overstating crypto guarantees

## What should not change

These remain fixed across all phases:

- no backup
- no recovery
- no password reset
- old-device-required trusted-device join
- device-bound identity
- ciphertext-like server storage only
- no plaintext push payloads
- no hidden admin or decryption surface

## What Codex can keep doing automatically

Inside the repository, ongoing automation can continue for:

- search/history hardening
- messaging reliability and state-machine cleanup
- UI/system polish
- CI and release-gate tightening
- docs and test expansion

Outside the repository, these still require humans and external systems:

- audited crypto selection and validation
- APNs/FCM credentials
- real-device profiling
- external security review execution
