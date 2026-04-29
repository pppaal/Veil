# Audit RFP — outbound email template (English)

Use this verbatim or as a base. Fill the bracketed values, attach the
packet (see "Attachments" at the bottom), commit SHA pinned, and send
from a personal address that you can guarantee will reply within 24h.

---

**To:** mario@cure53.de  *(or contact@cure53.de / the firm's RFP form)*

**Subject:** External cryptographic review — VEIL (private-beta E2E messenger)

---

Hi [first-name],

I'm the maintainer of [VEIL](https://github.com/pppaal/veil), a
privacy-first end-to-end encrypted messenger currently in private
beta. The product premise is **no backup, no recovery, device-bound** —
a tighter posture than Signal or WhatsApp default to. We treat that as
a non-negotiable, enforced by `scripts/policy-check.mjs` at CI time.

Before we open beta to a wider audience or flip the production gate
(`VEIL_AUDITED_CRYPTO_ATTESTED`), we need an external cryptographic
review.

## Tech stack at a glance

- Backend: NestJS + Prisma + Postgres + Redis + MinIO. Server is
  ciphertext-only; policy-check enforces no plaintext in push, no admin
  message viewer, no recovery flow.
- Mobile (Flutter): full Signal-style double ratchet implemented in
  `apps/mobile/lib/src/core/crypto/lib_crypto_adapter.dart`
  (X25519 + HKDF-SHA256 + AES-256-GCM). Session state persisted in
  encrypted secure storage.
- Web demo: simpler per-message ECDH (no DH ratchet yet) — Phase W
  spec exists, implementation deferred to post-audit.
- Group chats: shared conversation key today; Sender Keys design in
  `docs/group-sender-keys-design.md`, not implemented.
- Sealed Sender: design in `docs/sealed-sender-design.md`, not
  implemented.
- Authentication: Ed25519 challenge/verify with JTI blacklist + WS
  force-disconnect on logout.

## Review scope (priority order)

1. Mobile double-ratchet implementation (Dart)
2. Existing forward-secrecy spec (`docs/forward-secrecy-ratchet-design.md`)
3. Envelope v3 unified spec (`docs/envelope-v3-unified-spec.md`) —
   not yet implemented; review the spec for soundness so we don't
   ship known-bad
4. Group Sender Keys spec (`docs/group-sender-keys-design.md`) —
   spec only
5. Sealed Sender spec (`docs/sealed-sender-design.md`) — spec only
6. Backend auth + device transfer (`apps/api/src/modules/auth`,
   `apps/api/src/modules/device-transfer`)
7. Backend message routing (`apps/api/src/modules/messages`)

We're explicitly **not** asking you to review:
- iOS/Android packaging (separate)
- WebRTC scaffolding (under construction)
- TLS / network transport (handled by Caddy + Cloudflare)
- HR/business processes (this is engineering review)

## Deliverables we'd like

- HTML or PDF report. We're happy with executive summary + per-finding
  detail.
- Findings JSON compatible with the schema in
  `artifacts/external-review-findings-template.json` (we generate this
  with `pnpm beta:external:bundle`).
- 30-minute walkthrough call with the lead reviewer at the end.
- 2 weeks of asynchronous follow-up so we can ask "is this finding
  fully addressed by the patch in commit XYZ".

## Timeline

- Ideal: 4-6 weeks wall clock
- Hard ceiling: 8 weeks
- Start: as soon as NDA signed

## Pricing context

We're a single-developer beta, not a funded startup. If your typical
engagement floor is over our budget, we'd love to hear about a
narrower-scope option (e.g. mobile ratchet only, or spec review only).
We've also applied for OTF funding which may cover some or all of the
cost — happy to coordinate if you've worked with OTF before.

## Attachments

- `external-security-review-packet.md` — full packet manifest
- `forward-secrecy-ratchet-design.md` — current spec
- `envelope-v3-unified-spec.md` — next spec
- `group-sender-keys-design.md` — group spec
- `sealed-sender-design.md` — sealed spec
- Repo URL with audit-pinned commit SHA: [TODO commit SHA]
- Pinned tag: [TODO tag]

Happy to NDA before any further detail. Looking forward to your
response.

Thanks,

[Your name]
[Your contact]
[GitHub handle / signal handle]

---

## Notes for sender

- Wait 5-7 business days for response. Cure53 / NCC are responsive.
  Trail of Bits' inbound queue is heavier.
- If no response in 7 days, send a one-line follow-up. If still
  silent, move to the next firm in `external-audit-firm-shortlist.md`.
- When you get a "what's your budget" response, the honest answer
  here is "we'd like to spend $30-60K, but we can flex if scope
  matches". Anchor low.
- After NDA but before contract, send the actual packet bundle (run
  `pnpm beta:external:bundle` to get the JSON manifests).
