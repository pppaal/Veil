# OTF (Open Tech Fund) 신청서 템플릿

OTF 의 Internet Freedom Fund 또는 Surveillance Self-Defense Fund 에
신청해서 무료 또는 보조금 보안 검토를 받기 위한 초안. opentech.fund
사이트의 공식 신청서 항목 순서로 정리.

---

## 1. Project name

VEIL — privacy-first end-to-end encrypted messenger

## 2. One-sentence description

A no-backup, no-recovery, device-bound end-to-end encrypted messenger
that encodes the privacy invariants in policy-check CI rather than
documentation, designed for users who require an "if I lose this
device, the conversation is gone forever" guarantee.

## 3. Project URL / repository

https://github.com/pppaal/veil

## 4. License

[TODO — confirm; assumes MIT or AGPL-3.0]

## 5. Mission alignment (max 500 words)

VEIL is built to occupy a posture that mainstream messengers
deliberately avoid: **no recovery exists**. Signal, WhatsApp, and
iMessage all default-on a recovery path (PIN, encrypted iCloud backup,
linked devices) because user-experience research says most users
consider losing chat history unacceptable. That tradeoff makes those
platforms safer for everyday use but strictly weaker for users whose
threat model includes coerced unlock of a backup, lawful seizure of
cloud data, or compromise of the recovery PIN itself.

VEIL inverts the default: **there is no recovery flow, by design and
in code**. `scripts/policy-check.mjs` fails the build if the auth
module ever introduces `password reset|recovery`, if the push module
ever references `messageBody|plaintext|ciphertext`, or if any path
introduces an admin message viewer. The policy is mechanically
enforced, not documented.

This posture is exactly what OTF's Internet Freedom Fund describes:
tooling that protects journalists, activists, and at-risk users in
contexts where the threat is not the network but the device or the
service operator under coercion. The mainstream "encrypted" market is
crowded; the "no-recovery, device-bound" niche is largely vacant
outside Threema (closed-source, paid, EU-only).

We have shipped:
- a Signal-style double ratchet on Flutter mobile
- atomic device transfer with old-device revocation in a single
  serializable transaction
- ciphertext-only server policy enforced in CI
- 132+ unit tests, 6+ e2e tests, all passing on every commit
- comprehensive operator runbooks (abuse-triage, tester-guide,
  data-subject-rights)

What we lack and need OTF help with: an external cryptographic review.
Without it we will not ship to a public audience.

## 6. Specific request

A funded external cryptographic review by Cure53, Trail of Bits, NCC
Group, or equivalent. Estimated scope:

- 4-6 weeks wall clock
- Mobile ratchet implementation review
- Spec review for the three pending designs (envelope v3 unified, group
  sender keys, sealed sender)
- Backend auth + device transfer review
- Public report

Preferred budget: $30K-$80K. Open to a smaller-scope engagement if
that's what fits the program.

## 7. Project history

- 2025 Q4 — Initial scaffolding
- 2026 Q1 — Backend feature parity, mobile crypto adapter, web demo
- 2026 Q2 — Production deploy stack, observability, voice messages,
  device-transfer atomic revoke
- 2026 Q2 (current) — Awaiting external audit before public beta

132 unit tests + 6 e2e tests + policy-check passing on every commit.
Codebase ~25K lines.

## 8. User base

Currently private beta with the maintainer's social circle. Public
beta is gated on this audit. Target user base for v1: 100-1000
testers, mostly Korean-speaking, in privacy-sensitive professions
(journalists, activists, lawyers, healthcare workers).

## 9. Risks if NOT funded

Without an external audit, we cannot in good conscience ship to a
public audience. The current code may contain crypto bugs that a
well-resourced attacker could exploit. We have built every defensive
layer we can (policy-check, atomic transfer, redacted logging, no
plaintext in push) but those don't substitute for adversarial review of
the actual ratchet implementation.

If unfunded, the project ships only to the maintainer's friends and
languishes — a privacy-niche messenger that exists but doesn't reach
the audience that needs it.

## 10. Risks if funded

Standard risks of releasing a privacy tool: nation-state surveillance
attention, abuse for criminal coordination, regulatory pressure
(particularly Korean comm-secrecy laws). We have abuse-triage runbooks,
a data-subject-rights process aligned with PIPA/GDPR, and a tester
guide that explicitly warns users about beta-stage limitations.

## 11. Maintainer details

- [TODO maintainer name + brief bio]
- [TODO contact email]
- [TODO PGP / signal handle for sensitive communication]
- Past projects / relevant experience: [TODO]
- Time commitment: [TODO — currently part-time? full-time?]

## 12. Why now?

The audit-blocking codebase is stable. Three weeks of OTF review
followed by 4-6 weeks of audit-firm engagement aligns with our planned
public beta launch in Q3 2026.

## 13. Diversity / outreach plan

[TODO — explain how the project will reach the actual at-risk users
once shipped, what languages it'll support, what onboarding looks like
for non-technical journalists / activists]

## 14. Attachments to include

- Architecture overview (`docs/architecture.md`)
- Threat model (`docs/threat-model.md`)
- No-recovery rationale (`docs/no-recovery.md`)
- External review packet (`docs/external-security-review-packet.md`)
- Three crypto design docs (envelope v3, sender keys, sealed sender)
- Audit firm shortlist (`docs/external-audit-firm-shortlist.md`)
- Pinned audit-ready commit SHA: [TODO]

---

## Submission notes

- OTF accepts applications year-round; rolling review.
- Decision in 6-8 weeks typically.
- If accepted, OTF matches you to a vetted firm — you don't pick.
  Common matches: Cure53, ROSS, Radically Open Security.
- OTF retains the right to publish the report (we already plan to).
- Conflict-of-interest disclosure: list any prior consulting
  relationships with potential auditors.
