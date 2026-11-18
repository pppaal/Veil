# App Store listing (draft)

Target storefront: Apple App Store (iOS, iPadOS, macOS Catalyst).
Bundle identifier: `app.veil.messenger` (placeholder; align with
`apps/mobile/ios/Runner.xcodeproj`).

> **Legal review required** for every user-facing string below before
> submission. This is a starting draft, not reviewed copy.

The texts below are the fields of `store/appstore/metadata-en.txt`; change
them there and here together.

## App name (30 chars)

`Veil: Encrypted Messenger`

## Subtitle (30 chars)

`Chat without a phone number`

## Promotional text (170 chars, updatable without review)

Sign up with a handle, not a phone number. Messages are end-to-end encrypted, so only you and the people you talk to can read them.

## Description

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
- Move your account to a new phone

There is no backup and no account recovery. If you lose your phone, you lose the account and its messages.

Veil runs on one phone at a time. Moving to a new phone moves your handle to it and signs the old phone out. Your message history does not move.

No ads, no tracking and no third-party analytics. The code is open source.

Privacy policy: https://pppaal.github.io/Veil/
Contact: privacy@veil.app

Not in the mobile build, so not in this listing: view-once messages, calls
and voice messages, and an online status (no one else ever sees whether you
are online). Add a bullet only when its screen ships.

## Keywords (100 chars, comma-separated)

`private,secure,e2ee,handle,username,disappearing,one-time link,app lock,safety number,pin`

No word of the name or the subtitle (App Store indexes those already) and
no other app's name.

## Category

- Primary: **Social Networking**
- Secondary: **Productivity**

## Age rating

17+ (unrestricted web access not enabled, but user-generated content is
end-to-end encrypted so we cannot moderate private content). The mobile app
reports and blocks accounts from a chat, a message and a contact, as App
Review expects in an app with user-generated content (guideline 1.2).

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
```

## Screenshot guide

The shot list, the sizes and how to capture them are in
[`store/appstore/screenshot-spec.md`](../../store/appstore/screenshot-spec.md):
six shots per iPhone size, captured on the iOS Simulator. The Xcode project
still builds for iPad as well (`TARGETED_DEVICE_FAMILY = "1,2"`), and App
Store Connect asks for iPad screenshots for such a build: set the device
family to iPhone before archiving, as the spec plans, or capture a 13" iPad
set too. The shots cannot be rendered like the Google Play set
(`store/play/screenshots/`), because iOS draws SF Pro, which the renderer
does not have.

Asset directory: `apps/mobile/ios/fastlane/screenshots/` (not yet
configured).

## Review notes for Apple

Paste the following block into "App Review Information → Notes"
([`store/appstore/app-review-notes.md`](../../store/appstore/app-review-notes.md)
has the full walkthrough):

```
No login is needed. Veil has no password, phone number or email: open the
app, accept the privacy notice, tick the box on "Before you start", and
pick any free handle (for example reviewer_a). The app creates the account
on the phone.

To send messages, use two devices or simulators, each with its own handle,
and start a chat from one to the other's handle. Messages show only on
those two devices.

Messages are end-to-end encrypted, so we cannot show their content to the
review team.
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
- [ ] `Info.plist` asks only for what the build uses:
      `NSFaceIDUsageDescription` (app lock) and
      `NSPhotoLibraryUsageDescription`, which the photo picker plugin
      requires even though the system picker never asks for access. No
      camera, microphone or photo-library-add usage string. If App Store
      Connect asks for a camera string on upload (`image_picker_ios` and
      `flutter_file_dialog` reference camera APIs), do not add one: call
      PHPicker and the document picker from the app's own code instead
- [ ] Push entitlement only if push is actually wired to APNs for this
      build (otherwise reject-risk)
- [ ] App Privacy answers transcribed from `store/appstore/app-privacy-answers.md`
      (no crash-reporting SDK added since; adding one changes the answers)
