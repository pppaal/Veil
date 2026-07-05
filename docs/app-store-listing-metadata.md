# Store Listing Metadata & Review Notes (draft)

_Draft copy for App Store Connect (iOS) and Google Play. Fill/adjust before
submission. Companion to `docs/app-store-submission-checklist.md`._

> **Do not submit yet** — gated on the external crypto audit (see the checklist).
> This is the copy to have ready so submission is a fill-in-the-form step once
> the gate clears.

Bundle ID / applicationId: `io.veil.mobile`. App supports `ko`, `en`, `ja` —
localize the primary fields for each store locale.

---

## App name & subtitle

- **App name:** VEIL — Private Messenger
- **Subtitle (iOS, ≤30 chars):** No number. No backup. No leaks.
- **Promotional text (iOS, ≤170 chars, updatable without review):**
  End-to-end encrypted messages with no phone number and no account. Nothing is
  stored in plaintext, ever. Your device is your identity.

## Description (English)

```
VEIL is an open-source, end-to-end encrypted messenger built on one idea:
the server should never be able to read your messages — and neither should we.

• No phone number, no email, no account. Your device is your identity.
• End-to-end encryption (X25519 + AES-256-GCM, Double Ratchet forward secrecy).
• No cloud backup, no password reset, no admin override — by design.
• The server only ever relays ciphertext. It cannot decrypt your conversations.
• Open source (AGPL-3.0): anyone can read the code and verify these claims.

IMPORTANT — read before you install:
VEIL has NO account recovery. If you lose your device or wipe the app, your
conversations are gone permanently. There is no backup and no reset. That
tradeoff is the product: no recovery path means no backdoor.

Messaging: text, voice messages, photos and files, reactions, replies, edits,
disappearing timers, and block/mute controls.
```

## Description (Korean)

```
VEIL은 오픈소스 종단간 암호화 메신저입니다. 서버가 당신의 메시지를 절대 읽을
수 없도록 설계되었습니다.

• 전화번호도, 이메일도, 계정도 없습니다. 기기 자체가 신원입니다.
• 종단간 암호화 (X25519 + AES-256-GCM, Double Ratchet 순방향 비밀성).
• 클라우드 백업 없음, 비밀번호 재설정 없음, 관리자 우회 없음 — 의도된 설계입니다.
• 서버는 암호문만 중계하며, 대화를 복호화할 수 없습니다.
• 오픈소스(AGPL-3.0): 누구나 코드를 읽고 검증할 수 있습니다.

설치 전 필독:
VEIL에는 계정 복구가 없습니다. 기기를 잃거나 앱을 지우면 대화는 영구히
사라집니다. 백업도, 재설정도 없습니다. 이 트레이드오프가 바로 제품의 핵심입니다.
복구 경로가 없다는 것은 백도어도 없다는 뜻입니다.
```

## Keywords (iOS, ≤100 chars, comma-separated)

`encrypted,messenger,privacy,e2e,secure chat,no phone number,open source,anonymous,private`

## Category & age rating

- Primary category: **Social Networking** (alt: Utilities).
- Age rating: expect **17+** — unfiltered user-generated messaging. Answer the
  ITunes/Play content questionnaire truthfully (user communication, no
  moderation of E2E content is possible by design; mention client-side
  block/report).

## Privacy "nutrition label" (App Store Connect) — answer precisely

VEIL cannot read message content, so most "linked to you" data does not apply.
Declare only what the server actually retains — cross-check against
`apps/api/src/common/config/env.schema.ts` and the threat model:

- **Data NOT collected:** message content, contacts, precise location, browsing
  history, photos (transit only, encrypted).
- **Data that MAY be collected (not linked to identity where possible):**
  - Coarse diagnostics / crash data — only if a crash reporter is enabled
    (currently none wired; keep it that way or declare it).
  - Device/push identifiers — only once APNs/FCM is enabled
    (`VEIL_PUSH_PROVIDER` is `none` today).
- **Metadata retention (server):** terminal call records and consumed prekeys
  are swept after `VEIL_CALL_RECORD_RETENTION_DAYS` /
  `VEIL_PREKEY_CONSUMED_RETENTION_DAYS` (default 30 days). Reflect this honestly.

## App Review notes (paste into "Notes for Reviewer")

```
VEIL is an end-to-end encrypted messenger. Two behaviors commonly mistaken for
bugs are intentional privacy design — please read before testing:

1. NO ACCOUNT / NO PHONE NUMBER. There is no sign-up form. Identity is bound to
   the device on first launch. This is not a broken onboarding flow.

2. NO RECOVERY. There is deliberately no password reset, no cloud backup, and no
   way to restore a conversation on a new device without the original device.
   Losing the device permanently loses the data. This is core to the product
   (no recovery path = no backdoor) and is disclosed prominently in-app.

Encryption: uses standard cryptography (X25519, AES-256-GCM, Ed25519). Export
compliance is declared (ITSAppUsesNonExemptEncryption=true) and the annual
self-classification is on file.

Source is public under AGPL-3.0 for independent verification.

Test walkthrough: launch → device identity is created automatically → start a
conversation → send text/voice/photo → reactions and replies work inline. No
credentials are required to reach full functionality.
```

## Support / marketing URLs (fill in)

- Support URL: `https://…` (required)
- Marketing URL: `https://…` (optional)
- Privacy Policy URL: `https://…` (required — must state no-plaintext-on-server,
  metadata retention windows, no third-party sharing)

## Screenshots checklist

- iOS: 6.7" (iPhone 15/16 Pro Max) and 6.5"/5.5" fallback sets.
- Suggested shots: onboarding "no recovery" warning, a conversation, voice
  message, attachment preview, settings/theme. Use fictional content — no real
  user data.
- Google Play: phone + 7"/10" tablet if declared; feature graphic 1024×500.
