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

The listing text lives in `store/play/title-en.txt`, `short-en.txt`,
`full-en.txt` and `store/appstore/metadata-en.txt`; this page repeats it.

- **App name (both stores, ≤30 chars):** Veil: Encrypted Messenger
- **Subtitle (iOS, ≤30 chars):** Chat without a phone number
- **Short description (Google Play, ≤80 chars):** Encrypted chat with a handle, not a phone number. No email, no real name.
- **Promotional text (iOS, ≤170 chars, updatable without review):**
  Sign up with a handle, not a phone number. Messages are end-to-end encrypted, so only you and the people you talk to can read them.

## Description

The same text on both stores:

Veil is a messenger you sign up for with a handle. No phone number, no email, no real name.

Messages are end-to-end encrypted on your phone, so only you and the people you talk to can read them. The server keeps only encrypted copies it can't read, for 30 days at most.

- One-to-one and group chats
- Photos and files
- Disappearing messages
- Read receipts and typing indicators you can turn off
- Safety numbers to check who you're talking to
- One-time links for a password or a note
- App lock with a PIN or biometrics
- Block or report someone, and mute a chat
- Warns about common scam messages and look-alike accounts, with checks on your phone. Chats from accounts you haven't talked to wait as requests.
- Move your account to a new phone

There is no backup and no account recovery. If you lose your phone, you lose the account and its messages.

Veil runs on one phone at a time. Moving to a new phone moves your handle to it and signs the old phone out. Your message history does not move.

No ads, no tracking and no third-party analytics. The code is open source.

Privacy policy: https://pppaal.github.io/Veil/
Contact: privacy@veil.app

## Keywords (iOS, ≤100 chars, comma-separated)

`private,secure,e2ee,handle,username,disappearing,one-time link,app lock,safety number,pin`

## Category & age rating

- Primary category: **Social Networking** (alt: Utilities).
- Age rating: expect **17+** for unfiltered user-generated messaging. Answer the
  ITunes/Play content questionnaire truthfully (user communication, no
  moderation of E2E content is possible by design; the mobile app blocks and
  reports accounts, so say so).

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
   asks for a handle (Choose a handle) and creates the account on the phone.
   This is not a broken onboarding flow.

2. No recovery. There is no password reset, no cloud backup, and no way to
   restore a chat on a new phone without the old phone. Losing the phone
   loses the data for good. The app says so on "Before you start", before
   the account is created.

Encryption: uses standard cryptography (X25519, AES-256-GCM, Ed25519). Export
compliance is declared (ITSAppUsesNonExemptEncryption=true) and the annual
self-classification report will be filed before distribution.

Source is public under AGPL-3.0 for independent verification.

Test walkthrough: launch → agree to the privacy notice → Before you start →
Choose a handle (any free handle) → New chat with a second device's
handle → send a text message → long-press it to react → tap + to send a
photo or a file. No credentials are required to reach full functionality.
Calls and voice messages are not part of this build.
```

## Support / marketing URLs (fill in)

- Support URL: `https://…` (required)
- Marketing URL: `https://…` (optional)
- Privacy Policy URL: `https://…` (required; it must state no-plaintext-on-server,
  metadata retention windows, no third-party sharing)

## Screenshots checklist

- iOS: the 6.9" and 6.5" iPhone sets of `store/appstore/screenshot-spec.md`,
  plus a 13" iPad set if the archived build still runs on iPad (the Xcode
  project targets iPhone and iPad today).
- The six shots are the ones the spec lists, the same six screens as the
  Google Play set, with the demo account of the layout gate. Show nothing
  the build does not have: no call or voice message screen.
- Google Play: the phone screenshots and the 1024×500 feature graphic are in
  `store/play` (`store/play/screenshots/README.md` says how they are made).
  Play does not require tablet screenshots, and none are made.
