# External Crypto Audit — Vendor Outreach Template

Use this as the first message to any shortlisted auditor. Keep it short; the technical packet does the rest.

## Shortlist suggestions (as of 2026-04)

- **Trail of Bits** — strong in applied cryptography, mobile E2EE review history
- **Cure53** — deep Flutter/mobile app audit track record
- **NCC Group** — full-stack + protocol review
- **Radically Open Security** — EU-based, cost-competitive
- **A41** (Korean) — if Korean-language deliverables are required

Pick 2–3, send the message below in parallel, compare scope + price.

## Email template

> Subject: External cryptographic and mobile security review — VEIL private-beta messenger
>
> Hello,
>
> We are preparing VEIL, a privacy-first messenger targeting public launch in South Korea, for external cryptographic and mobile security review before we lift our production-boot block.
>
> **Scope we want reviewed**
> - E2EE adapter implementation (X25519 + AES-256-GCM + Ed25519 + HKDF-SHA256)
> - Key handling, device-bound identity, trusted-device graph, device transfer
> - Metadata exposure surface on the relay server
> - Mobile secure-storage posture (Flutter, iOS Keychain, Android Keystore)
> - Push payload privacy (APNs/FCM)
>
> **Explicitly out of scope**
> - Backend infrastructure hardening beyond what touches ciphertext handling
> - Third-party library CVE scanning (we do that separately)
>
> **Deliverables we need**
> - Severity-tagged findings (Critical/High/Medium/Low/Info)
> - Remediation guidance per finding
> - Short public statement we can reference after patching
> - Optional: retest pass after remediation
>
> **Packet we will provide once NDA is signed**
> - `docs/external-security-review-packet.md` as the entry point
> - Architecture, threat model, message/attachment/transfer flows
> - Crypto adapter boundary docs
> - Current commit SHA and reproducible build manifest
> - `artifacts/external-security-review-manifest.json`
>
> **Timeline we are aiming for**
> - Kickoff: [DATE]
> - Findings delivery: [DATE + 4 weeks]
> - Retest: [DATE + 6 weeks]
>
> **Budget expectation**
> Please quote a fixed-scope engagement. We will not negotiate deliverables downward once the review begins.
>
> Let us know if you need anything additional before you can quote.
>
> —
> VEIL security contact
> privacy@veil.app

## NDA and legal

- Ask the auditor's standard mutual NDA first; do not propose your own unless necessary.
- Confirm they can deliver findings in English; Korean translation is a bonus.
- Confirm retest terms and re-quote policy for out-of-scope findings.

## Post-engagement hygiene

When findings arrive, record each in
[external-review-remediation-tracker.md](external-review-remediation-tracker.md),
patch in-repo, re-run verification per [external-security-review-packet.md](external-security-review-packet.md),
and attach retest evidence before declaring production-ready.
