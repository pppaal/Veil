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
- Protocol v2 (`docs/crypto-envelope-spec.md`, normative): X3DH with
  signed and one-time prekeys that authenticates both parties, then a
  Double Ratchet with AES-256-GCM (X25519, Ed25519, HKDF-SHA256).
  Implemented on both clients and pinned byte for byte by
  `packages/shared/test-vectors/crypto-kat.json`, which an independent
  node:crypto implementation (`scripts/crypto-test-vectors.mjs`) and both
  clients reproduce.
- Mobile (Flutter): `apps/mobile/lib/src/core/crypto/` (`x3dh/`,
  `ratchet/`, `payload/`, `attachment/`), with session state in OS secure
  storage. A trust-on-first-use layer decides which identity keys a
  conversation may use (`apps/mobile/lib/src/features/conversations/data/messenger/`).
- Web client: the second protocol-v2 implementation, on WebCrypto with
  non-extractable keys (`apps/web-demo/src/crypto/`, its trust pins and
  storage).
- Group chats: new mobile groups use Sender Keys
  (`docs/group-sender-keys-design.md`, implemented on mobile, pre-audit);
  groups created by older clients keep a shared conversation key.
- Sealed Sender: design in `docs/sealed-sender-design.md` is under
  revision and not implemented.
- `docs/envelope-v3-unified-spec.md` is superseded and was never
  implemented; it is history only.
- Authentication: Ed25519 challenge/verify with JTI blacklist + WS
  force-disconnect on logout; account deletion, revoking the calling or
  last device, and approving a device transfer also need a signature by
  the device's key.

## Review scope (priority order)

1. Protocol v2 on mobile (Dart) and web (WebCrypto) against
   `docs/crypto-envelope-spec.md`, including web/mobile byte parity
2. The identity-trust layer on both clients (pins, identity-change
   handling, safety numbers)
3. Sender Keys on mobile (`docs/group-sender-keys-design.md`)
4. The key directory and prekeys API (`apps/api/src/modules/prekeys`)
   and the group key-distribution relay (`apps/api/src/modules/groups`)
5. Backend auth, step-up proofs and device transfer
   (`apps/api/src/modules/auth`, `apps/api/src/modules/device-transfer`)
6. Backend message routing (`apps/api/src/modules/messages`)
7. The sealed-sender spec revision (`docs/sealed-sender-design.md`) —
   spec only

The full list of documents and code paths is generated from
`scripts/audit-scope.mjs` into the handoff bundle.

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
narrower-scope option (e.g. protocol v2 on one client only).
We've also applied for OTF funding which may cover some or all of the
cost — happy to coordinate if you've worked with OTF before.

## Attachments

- `external-security-review-packet.md` — full packet manifest
- `crypto-envelope-spec.md` — protocol v2, normative
- `crypto-surfaces.md` — where each cryptographic operation happens
- `group-sender-keys-design.md` — Sender Keys, implemented on mobile
- `sealed-sender-design.md` — sealed sender, under revision
- the handoff bundle from `pnpm audit:handoff`, which carries the rest
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
