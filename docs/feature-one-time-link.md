# Feature spec — One-time secret link (일회성 비밀 링크)

A self-destructing, end-to-end encrypted message that anyone can open from
a link — **the recipient does not need the app**. This is VEIL's growth
wedge: every link sent exposes a non-user to VEIL and gives them a reason
to install, which is the one mechanic that works *without* solving the
messenger cold-start (your friends don't have to be on it yet).

Working prototype: [`docs/prototypes/one-time-link.html`](prototypes/one-time-link.html)
(open in any browser — real WebCrypto, no backend).

## User flow

1. Sender writes a secret, optionally adds a passphrase, taps **보안 링크 생성**.
2. They share the link (KakaoTalk, SMS, email — any channel).
3. Recipient opens it in a browser, reads the secret **once**, and it is gone.
4. Optional: a "Get VEIL" CTA on the view page → install funnel.

## Cryptography

AES-256-GCM with a 96-bit random IV. Two key modes:

| Mode | Where the key lives | Use when |
| --- | --- | --- |
| **Key-in-link** (default) | 256-bit random key in the URL **fragment** (`#…`) | one-tap convenience |
| **Passphrase** | key derived via PBKDF2-SHA256 (210k iters) from a passphrase the sender shares out-of-band; only the salt travels | the link channel itself isn't trusted |

The URL **fragment is never sent to the server** by browsers, so in the
key-in-link mode the server (in Model B below) only ever holds ciphertext.
GCM's auth tag gives tamper detection for free — a modified link fails to
decrypt rather than returning garbage.

Payload format: `v1.<iv>.<ciphertext>.<k|p>.<key|salt>` (all base64url).

### Verified properties (prototype, headless WebCrypto)

- key-in-link round-trips; passphrase round-trips
- plaintext never appears in the link (server-blind)
- passphrase mode keeps the key out of the link (salt only)
- wrong passphrase rejected; tampered payload rejected (GCM)

## Two delivery models

**Model A — link carries the ciphertext (the prototype).** Zero backend,
nothing stored anywhere; the encrypted blob lives in the link. Great for
short secrets and an instant demo. Limitation: it can't *enforce*
one-time/expiry (whoever holds the link can open it repeatedly) and URLs
cap payload size.

**Model B — burn-after-read blob store (the product).** Client encrypts,
`POST`s only the **ciphertext** to the API which returns an opaque id; the
key stays in the fragment. The link is `…/s/<id>#<key>`. First `GET`
streams the blob and **deletes it server-side atomically**; later opens 404
with a "이미 열렸거나 만료됨" page. Adds: true single-read, TTL expiry,
larger payloads/attachments, optional "notify me when opened."

Model B fits VEIL's existing stack: the `apps/api` envelope/attachment
storage already does encrypted-blob handling, and `veil://` deep links can
carry the fragment into the app when it *is* installed.

## Threat model / limits (be honest in the UI)

- A malicious recipient can screenshot or copy before "burn" — one-time
  means one *fetch*, not DRM. Say so.
- Key-in-link mode trusts the sharing channel: anyone who sees the full
  link can read it once. Passphrase mode removes that assumption.
- Model B's server learns metadata (size, timing, IP) but never plaintext
  or keys. Document retention = "until first read or TTL, then purged."

## Why this first (growth)

- Only mechanic that grows **without** network effects — recipients are
  non-users by definition.
- Closest to existing code (envelope crypto + blob storage), so it ships
  fast.
- "오픈소스 암호화 일회성 전송" is independently share-worthy on Korean dev
  communities (GeekNews) and pairs with the AGPL/auditable story.

## Build outline (Model B)

1. API: `POST /s` (store ciphertext + TTL → id), `GET /s/:id` (read-and-
   delete, atomic), `DELETE /s/:id`. No auth required to read; rate-limit
   creation.
2. Web view page at `/s/:id` that pulls the blob, decrypts with the
   fragment key, renders once, offers the install CTA.
3. Mobile: compose + share sheet entry; open `veil://s/<id>#<key>` natively.
4. Abuse controls: creation rate-limit, max size, max TTL, report link.
