# Google Play listing (draft)

Target storefront: Google Play.
Application ID: `app.veil.messenger` (placeholder; align with
`apps/mobile/android/app/build.gradle.kts`).

> **Legal review required** for every user-facing string below before
> publishing. This is a starting draft, not reviewed copy.

The three texts below are the files in `store/play` (`title-en.txt`,
`short-en.txt`, `full-en.txt`); change them there and here together.

## App title (30 chars)

`Veil: Encrypted Messenger`

## Short description (80 chars)

`Encrypted chat with a handle, not a phone number. No email, no real name.`

## Full description

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

Not in the mobile build, so not in this listing: view-once messages, calls
and voice messages, and an online status (no one else ever sees whether you
are online). Add a bullet only when its screen ships.

## Category

- Primary: **Communication**

## Content rating

IARC rating questionnaire should be answered honestly:

- User-generated content: YES (we ship a messenger)
- Encrypted UGC not visible to the developer: YES
- In-app reporting: YES. A chat's menu, a message's long-press sheet and a
  contact's sheet file a report (`POST /safety/reports`): the account, the
  reason and which chat or message, never its text. The same chat menu and
  contact sheet block an account, and Settings > Privacy > Blocked accounts
  lists them. Google Play expects both in an app with user-generated
  content.
- Interactive features: chat only; no live video to strangers, no
  unmoderated public rooms

Expected rating band: **Teen** (13+), the band Signal sits in.

## Data safety form (Play Console)

Transcribe [`store/play/data-safety-answers.md`](../../store/play/data-safety-answers.md)
into Play Console → App content → Data safety. That file is the only source
of the answers and the Play counterpart of
`store/appstore/app-privacy-answers.md`; `scripts/store-label-check.mjs`
fails CI when the two disagree, when the server stores data they do not
declare, or when this page or any other document contradicts them. In short:

- **Collected, not shared, App functionality only, not optional:** User IDs
  (handle and account id); Device or other IDs (each device's id and, when
  the app registers one, its push token); Contacts (the in-app contact list,
  conversation membership and call records: Play's Contacts type covers
  social-graph information and call history); Other user-generated content
  (group and channel names and descriptions and device labels, which the
  server stores readable).
- **Collected as ciphertext the server cannot decrypt:** other in-app
  messages, photos, videos, voice recordings and files.
- **Not collected:** name, email address, phone number, address, location,
  financial and health data, app interactions, search and web history, crash
  logs and diagnostics (the crash log stays on the device; no crash-reporting
  SDK ships).
- Data is encrypted in transit: **Yes**. Users can request deletion: **Yes**
  (in-app Delete account).

Any change to what the server stores is a launch blocker until the answers
file and the Data safety form are amended together.

## Permissions

Declared in the app's `AndroidManifest.xml` and surfaced in Play Console:

| Permission               | Used for                          | Runtime prompt?   |
|--------------------------|-----------------------------------|-------------------|
| INTERNET                 | network                           | no                |
| POST_NOTIFICATIONS (33+) | message notifications             | yes (Android 13+) |
| VIBRATE                  | notification vibration            | no                |
| WAKE_LOCK                | push wake-ups, once push is wired | no                |
| USE_BIOMETRIC            | app lock                          | no (per-use)      |

The plugins' own manifests add nothing to this list:
`flutter_local_notifications` declares `VIBRATE` and `POST_NOTIFICATIONS`,
`local_auth_android` `USE_BIOMETRIC`, `image_picker_android` a file provider
and a disabled Photo Picker backport service, `url_launcher_android` one
activity that is not exported (`WebViewActivity`, which the app does not
use), and the rest none. The app's own manifest adds one file provider,
limited to the one cache folder a file is opened from, and a `<queries>`
entry for https links, so a link in a message can open in the browser. `test/platform/native_permissions_test.dart` reads every
plugin's manifest and fails on any other permission. Libraries the plugins
depend on add two more, which the merged manifest of a debug build shows
(CI's `android-build` job prints the list on every run):

- `USE_FINGERPRINT`, from `androidx.biometric` (which `local_auth_android`
  uses): a normal permission for the fingerprint API of Android 9 and older,
  with no prompt.
- `io.veil.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, which
  `androidx.core` declares at signature level so that only this app can send
  to its own runtime receivers.

Before submission, also read the release bundle's merged manifest
(`build/app/intermediates/merged_manifests/release/AndroidManifest.xml`) or
the permissions Play Console lists for the bundle, and add any other it shows
here.

No `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_*` or `READ_EXTERNAL_STORAGE`:
photos come from the system photo picker and files from the system document
picker, which need none, and none of its plugins declares them. No
`READ_CONTACTS`, no `ACCESS_FINE_LOCATION`, no `QUERY_ALL_PACKAGES`. A feature
that needs one of these declares it in the change that makes the feature
work, together with the matching usage string in `ios/Runner/Info.plist`
(`test/platform/native_permissions_test.dart` pins both lists).

## Support & policy URLs

- Privacy Policy: `https://veil.app/privacy`
- Support: `https://veil.app/support`

## Screenshot set

Six phone screenshots (1080 x 1920) and the 1024 x 500 feature graphic are
in `store/play`. `store/play/screenshots/README.md` lists them and says how
a Flutter test draws them from the app's screens. They follow the App Store
shot list, but they are not the App Store images: those are captured on the
iOS Simulator, since iOS draws a font the test cannot render.

## Google Play review notes

Paste into "App access" review form:

```
No login is needed. Veil has no password, phone number or email: open the
app, accept the privacy notice, tick the box on "Before you start", and
pick any free handle (for example reviewer_a). The app creates the account
on the phone.

To send messages, use two phones or emulators, each with its own handle,
and start a chat from one to the other's handle.

Messages are end-to-end encrypted, so we cannot show their content to the
review team.
```

## Release track plan

1. **Internal testing**: closed to the dev org, used for every push
   during release hardening.
2. **Closed testing (alpha)**: opt-in tester pool, about 50 testers, for
   at least 14 days before broader rollout.
3. **Closed testing (beta)**: 200 to 500 testers. Required for new
   personal-developer accounts per Play Console 2024 rules.
4. **Production**: staged rollout at 5%, 20%, then 100% over 7 days.

## Submission checklist

- [ ] Privacy policy URL returns 200
- [ ] Data Safety form matches `store/play/data-safety-answers.md` row for row,
      with no optimistic claims
- [ ] Content rating questionnaire answered honestly (UGC=yes, UGC
      encrypted=yes)
- [ ] Target API level meets Play's current requirement
- [ ] All permissions declared are actually used; nothing extra
- [ ] Store listing copy reviewed by legal
- [ ] Release track notes filed in `docs/launch/release-notes/`
- [ ] Closed testing pool has met Play Console's minimum-days-of-testing
      requirement (new personal-account requirement)
