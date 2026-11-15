# Store listing metadata and review notes (draft)

_Draft copy for App Store Connect (iOS) and Google Play. Fill in and adjust
before submission. Companion to `docs/app-store-submission-checklist.md`._

> **Do not submit yet:** submission waits for the external crypto audit (see
> the checklist). This is the copy to have ready so submission is a
> fill-in-the-form step once the audit is done.

Bundle ID / applicationId: `io.veil.mobile`. The app is English only (`en`):
fill in the English (U.S.) fields of each store and add no other
localization.

---

## App name and subtitle

- **App name:** Veil Messenger
- **Subtitle (iOS, ≤30 chars):** Encrypted messenger
- **Promotional text (iOS, ≤170 chars, updatable without review):**
  End-to-end encrypted messages with no phone number, no email and no real name.
  Message content is never stored in plaintext. Your account lives on your phone.

## Description

```
Veil is an open-source, end-to-end encrypted messenger. The server can't
read your messages, and neither can we.

• No phone number, no email and no real name. Your account lives on your phone.
• End-to-end encryption (X25519 and AES-256-GCM, with a Double Ratchet for
  forward secrecy).
• No cloud backup, no password reset and no admin override.
• The server only passes on ciphertext. It cannot decrypt your messages.
• Open source (AGPL-3.0): anyone can read the code and check these claims.

Before you install:
Veil has no account recovery. If you lose your phone or delete the app, your
messages are gone for good. There is no backup and no reset.

Messaging: text messages in one-to-one and group chats, reactions,
disappearing messages, and message search that stays on your phone.
```

## Keywords (iOS, ≤100 chars, comma-separated)

`encrypted,messenger,privacy,e2e,secure chat,no phone number,open source,anonymous,private`

## Category & age rating

- Primary category: **Social Networking** (alt: Utilities).
- Age rating: expect **17+** for unfiltered user-generated messaging. Answer the
  ITunes/Play content questionnaire truthfully (user communication, no
  moderation of E2E content is possible by design; the mobile app has no
  block or report screen yet, so claim none).

## Privacy "nutrition label" (App Store Connect): answer precisely

Transcribe `store/appstore/app-privacy-answers.md` (App Store) and
`store/play/data-safety-answers.md` (Google Play). They are the only source of
the answers, and `scripts/store-label-check.mjs` fails CI when this page or any
other document contradicts them. Veil cannot read message content, but the
server does keep metadata linked to the account. In short:

- **Collected and linked to the user, App Functionality only, no tracking:**
  - User ID and Device ID. The server also stores the push token a device
    registers with, next to its Device ID, and uses it only for wake-ups
    that carry no message content.
  - Contacts: the in-app contact list (which accounts the user added), a
    social graph. The phone's address book is never read.
  - Other User Content: group and channel names and descriptions and device
    labels (stored readable), and the metadata needed to deliver messages
    (who is in which conversation, message and receipt times, call records).
- **Collected and not linked:** Other User Content for the encrypted message
  payloads, photos and other attachments, which the server holds only as
  ciphertext it cannot decrypt.
- **Not collected:** precise or coarse location, browsing and search history,
  contact info (name, email address, phone number), purchases, usage data,
  and diagnostics: no crash reporter is wired, and adding one changes the
  answers.
- **Metadata retention (server):** terminal call records and consumed prekeys
  are swept after `VEIL_CALL_RECORD_RETENTION_DAYS` /
  `VEIL_PREKEY_CONSUMED_RETENTION_DAYS` (default 30 days). Reflect this honestly.

## App Review notes (paste into "Notes for Reviewer")

```
Veil is an end-to-end encrypted messenger. Two things that can look like bugs
are how the app is meant to work. Please read before testing:

1. No phone number and no email. There is no password, email or SMS sign-up.
   After the privacy notice and a short "Before you start" page, the app
   creates an account on the phone (Create account) and asks for a handle
   (Choose a handle). This is not a broken onboarding flow.

2. No recovery. There is no password reset, no cloud backup, and no way to
   restore a chat on a new phone without the old phone. Losing the phone
   loses the data for good. The app says so on "Before you start", before
   the account is created.

Encryption: uses standard cryptography (X25519, AES-256-GCM, Ed25519). Export
compliance is declared (ITSAppUsesNonExemptEncryption=true) and the annual
self-classification report will be filed before distribution.

Source is public under AGPL-3.0 for independent verification.

Test walkthrough: launch → agree to the privacy notice → Before you start →
Create account → Choose a handle (any free handle) → New chat with a second
device's handle → send a text message → long-press it to react. No
credentials are required to reach full functionality. Calls, attachments and
voice messages are not part of this build.
```

## Support / marketing URLs (fill in)

- Support URL: `https://…` (required)
- Marketing URL: `https://…` (optional)
- Privacy Policy URL: `https://…` (required; it must state no-plaintext-on-server,
  metadata retention windows, no third-party sharing)

## Screenshots checklist

- iOS: 6.7" (iPhone 15/16 Pro Max) and 6.5"/5.5" fallback sets.
- Suggested shots: onboarding "no recovery" warning, a conversation, the
  safety number screen, settings/theme. Use fictional content and no real
  user data. Show nothing the build does not have: no call, voice message or
  attachment screen.
- Google Play: phone + 7"/10" tablet if declared; feature graphic 1024×500.
