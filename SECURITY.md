# Security policy

VEIL is in **private beta** and **has not been externally audited**.
Crypto correctness is held to the standard described in
[`docs/threat-model.md`](docs/threat-model.md), but until an
independent cryptographic review completes the codebase should not be
considered production-grade. Setting `VEIL_AUDITED_CRYPTO_ATTESTED=true`
is reserved for that post-audit milestone.

## Reporting a vulnerability

Please report security issues privately, **not** through public GitHub
issues, public Discord, or social media.

Channels, in priority order:

1. **GitHub Security Advisory** —
   <https://github.com/pppaal/veil/security/advisories/new>.
   Preferred for everything that benefits from a coordinated CVE.
2. **Encrypted email** — `security@veil.example` *(replace with your
   real address before public release)*. PGP key fingerprint will be
   pinned in this file once published.
3. **Signal** — operator handle published at the same time as the PGP
   key.

If those channels are unavailable, file a GitHub issue that says
nothing more than "I have a security report; please reply with a
private channel" and wait for a response. Do **not** include details
in the public issue.

## What to include

- Affected commit SHA (or version tag).
- Reproduction steps or proof of concept.
- Impact assessment in your own words.
- Suggested remediation, if any.
- Your preferred attribution name and contact for the eventual
  advisory.

We aim to respond within **3 business days**, with a triage decision
in **7 business days**, and a fix or disclosure plan in **30 days**
for high-severity issues.

## Scope

In scope:

- Cryptographic flaws in `apps/mobile/lib/src/core/crypto/` or
  `apps/web-demo/app.js` envelope handling
- Authentication bypass (`apps/api/src/modules/auth`)
- Device transfer race conditions
  (`apps/api/src/modules/device-transfer`)
- Server-side acceptance of plaintext or non-ciphertext message bodies
- WebSocket gateway authorization gaps
- Attachment upload / download authorization gaps
- Push payload leakage of plaintext or envelope fields
- Logging or metrics leakage of handles, tokens, or message content

Out of scope (please don't report these as vulnerabilities):

- Missing security headers on third-party CDN-fronted assets
- Social-engineering attacks against the operator
- Physical attacks on a user's unlocked device
- DoS via volumetric attacks (we expect Cloudflare / WAF to absorb)
- Spam unrelated to authorization controls
- Vulnerabilities in unsupported beta forks of the project

If unsure whether something is in scope, send the report anyway and
we'll triage.

## Coordinated disclosure

We follow a **90-day** coordinated disclosure window from the moment
we acknowledge the report. If we cannot ship a fix in that window we
will negotiate an extension; if that fails the reporter is free to
disclose. We will publish a CVE and a public advisory at disclosure
time.

## Bug bounty

There is **no monetary bounty** during private beta. We will publicly
credit reporters in the advisory and the project changelog unless the
reporter prefers anonymity. Once a bounty program exists it will be
listed here.

## Hall of fame

We will add reporter credits here as advisories are published.

*(empty — first advisory pending)*

---

For policy invariants enforced in CI rather than via documentation,
see [`scripts/policy-check.mjs`](scripts/policy-check.mjs).

For the full external-review packet and audit firm outreach, see
[`docs/external-security-review-packet.md`](docs/external-security-review-packet.md)
and [`docs/external-audit-firm-shortlist.md`](docs/external-audit-firm-shortlist.md).
