# App Store listing (draft)

Target storefront: Apple App Store (iOS, iPadOS, macOS Catalyst).
Bundle identifier: `app.veil.messenger` (placeholder; align with
`apps/mobile/ios/Runner.xcodeproj`).

> **Legal review required** for every user-facing string below before
> submission. This is a starting draft, not reviewed copy.

## App name

**Veil Messenger**

## Subtitle (30 chars)

`Encrypted messenger`

## Promotional text (170 chars, updatable without review)

`End-to-end encrypted messages with no phone number, no email and no ads. Only you and the people you talk to can read them.`

## Description

Veil is an end-to-end encrypted messenger. What you send never leaves your
phone in a form the server can read.

- **The server can't read your messages.** It passes on encrypted messages
  and never sees what they say or what you attach.
- **No phone number.** No SMS code and no address book upload. You choose a
  handle and give it to the people you want to hear from.
- **Your account lives on your phone.** There is no cloud copy of it. If you
  revoke a phone, it loses access.
- **Disappearing messages.** Set a timer on a chat, and its messages are
  deleted from every device when the timer runs out.

Veil has no ads and no analytics, and there is no account recovery: if you
lose your phone, you lose the account.

Not in the mobile build, so not in this listing: view-once messages,
block, mute and report. The server has the endpoints; the app has no screen
for any of them yet. Put a bullet back when its screen ships.

## Keywords (100 chars, comma-separated)

`private,messenger,encrypted,chat,privacy,secure,no sms,no phone,signal,e2ee,disappearing`

## Category

- Primary: **Social Networking**
- Secondary: **Productivity**

## Age rating

17+ (unrestricted web access not enabled, but user-generated content is
end-to-end encrypted so we cannot moderate private content). The mobile app
has no reporting or blocking screen yet, though the server takes abuse
reports. App Review expects both in an app with user-generated content
(guideline 1.2): a launch blocker.

## Privacy nutrition label

Transcribe [`store/appstore/app-privacy-answers.md`](../../store/appstore/app-privacy-answers.md)
into App Store Connect → App Privacy. That file is the only source of the
answers; `scripts/store-label-check.mjs` fails CI when this page or any other
document contradicts it. In short:

- **Collected and linked to the user, for App Functionality only:** User ID
  and Device ID (with the device's push token); Contacts (the in-app contact
  list, a social graph; the phone's address book is never read); Other User
  Content (group and channel names and descriptions and device labels, which
  the server stores readable, and the metadata needed to deliver messages:
  who is in which conversation, message and receipt times, call records).
- **Collected and not linked:** Other User Content for the encrypted message
  payloads, which the server cannot decrypt.
- **Diagnostics:** Crash Data, Performance Data and Other Diagnostic Data are
  declared as not collected. The crash log stays on the device and the app
  ships no crash-reporting SDK; adding one changes the answers.
- The remaining categories (Contact Info, Location, Financial Info, Health &
  Fitness, Sensitive Info, Browsing History, Search History, Purchases, Usage
  Data and the rest) are declared as not collected, as the answers file lists.

### Tracking

**No tracking.** Veil declares `NSUserTrackingUsageDescription` absent and
does not request ATT consent because it performs no cross-app tracking.

## Support URLs

- Support: `https://veil.app/support`
- Marketing: `https://veil.app`
- Privacy Policy: `https://veil.app/privacy` (content mirrors
  `docs/privacy-policy-en.md` and `docs/privacy-policy-ko.md`)

## What's New (release notes template)

```
Release <version>

- <ship items>
- <bug fixes>

Nothing you send is stored on our servers in a form we can read.
```

## Screenshot guide

Ship 5 screenshots per device class (6.7" iPhone, 6.5" iPhone, 5.5"
iPhone, 12.9" iPad, 11" iPad). Consistent visual order:

1. Chats, with at least one disappearing-message timer visible. English
   only.
2. Safety number, the moment two people compare their numbers.
3. A chat with the disappearing-message timer set.
4. Settings: devices, app lock and privacy.
5. Choose a handle: sign-up without a phone number.

Asset directory: `apps/mobile/ios/fastlane/screenshots/` (not yet
configured). The shot list and sizes are in
[`store/appstore/screenshot-spec.md`](../../store/appstore/screenshot-spec.md).

## Review notes for Apple

Paste the following block into "App Review Information → Notes":

```
Veil is an end-to-end encrypted messenger. To sign in, the reviewer can
use the following test account:

  Handle: @appstore-review-<random>
  Transfer code: <generated per review, see README>

Veil does not use a phone number or email for onboarding. The reviewer
chooses a handle, and the app generates keys on-device. There is no
cloud account.

Because Veil is end-to-end encrypted, the server cannot display message
content to the review team. Test messages sent between the reviewer's
two installs will be visible only on those installs.
```

## Export compliance

Veil uses end-to-end encryption with only standard, published algorithms
(X25519, AES-256-GCM, Ed25519, HKDF-SHA256; see `docs/crypto-envelope-spec.md`).
It implements no proprietary cryptography, so it qualifies for the mass-market
self-classification exemption under 15 CFR 740.17(b)(1). For App Store
submission:

- `ITSAppUsesNonExemptEncryption` = `YES` (already set in `Info.plist`): the
  encryption is not OS/auth/HTTPS-only, so this is the truthful value.
- Do **not** add `ITSEncryptionExportComplianceCode`. That key is only for apps
  that hold an issued BIS CCATS/ERN. Standard-algorithm mass-market software
  self-classifies (ECCN 5D992.c) and needs **no CCATS**.
- In App Store Connect answer: encryption = Yes → qualifies for exemption →
  standard/published algorithms (not proprietary), and confirm the annual BIS
  self-classification report.
- File the annual BIS (crypt@bis.doc.gov) + NSA (enc@nsa.gov) self-classification
  report (ECCN 5D992.c) on first export and by Feb 1 each year.
- If distributing in France, file the ANSSI encryption declaration (or
  geo-restrict FR to skip it).

If the self-classification report isn't filed, submission answers can't be
completed truthfully.

## Localization

The app and the listing are English only. The privacy policy exists in
English and Korean (`docs/privacy-policy-en.md`, `docs/privacy-policy-ko.md`).

## Submission checklist

- [ ] Privacy policy URL responds with 200
- [ ] All test accounts work
- [ ] Annual BIS self-classification report filed (5D992.c) + French/ANSSI declaration filed (if FR distribution)
- [ ] Age rating questionnaire answered honestly (17+)
- [ ] No placeholders in Promotional text / Description
- [ ] Screenshots exist for every required device class
- [ ] Legal has reviewed "description" + "promotional text"
- [ ] `Info.plist` asks only for what the build uses: today that is
      `NSFaceIDUsageDescription` (app lock) alone. No camera, microphone or
      photo library usage string while the app sends text only
- [ ] Push entitlement only if push is actually wired to APNs for this
      build (otherwise reject-risk)
- [ ] App Privacy answers transcribed from `store/appstore/app-privacy-answers.md`
      (no crash-reporting SDK added since; adding one changes the answers)
