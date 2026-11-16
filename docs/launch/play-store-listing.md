# Google Play listing (draft)

Target storefront: Google Play.
Application ID: `app.veil.messenger` (placeholder; align with
`apps/mobile/android/app/build.gradle.kts`).

> **Legal review required** for every user-facing string below before
> publishing. This is a starting draft, not reviewed copy.

## App title (30 chars)

`Veil Messenger`

## Short description (80 chars)

`End-to-end encrypted messenger with no phone number, no email and no real name.`

## Full description

Veil is an end-to-end encrypted messenger. The server passes on encrypted
messages and never sees what they say.

**What you get**
- End-to-end encrypted messages.
- No phone number, no email and no address book upload. You pick a handle.
- Your account lives on your phone. There is no cloud account.
- Disappearing messages, with a timer on each chat.

**What you don't get**
- No ads and no analytics.
- No backups, local or cloud.
- No account recovery. If you lose your phone, you lose the account.
- No contact upload and no directory of who else uses Veil.

**Who it's for**
People who want to message without giving out a phone number, and who
accept that a lost phone means a lost account.

Not in the mobile build, so not in this listing: view-once messages,
block, mute and report. The server has the endpoints; the app has no screen
for any of them yet. Put a bullet back when its screen ships.

## Category

- Primary: **Communication**

## Content rating

IARC rating questionnaire should be answered honestly:

- User-generated content: YES (we ship a messenger)
- Encrypted UGC not visible to the developer: YES
- In-app reporting: NO in the current build. The server takes abuse reports
  (`POST /safety/reports`), but the mobile app has no screen that files
  one. Google Play expects in-app reporting and blocking in an app with
  user-generated content: a launch blocker. Answer YES once the screen
  exists.
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

Declared in `AndroidManifest.xml` and surfaced in Play Console:

| Permission                   | Used for            | Runtime prompt? |
|------------------------------|---------------------|-----------------|
| INTERNET                     | network             | no              |
| ACCESS_NETWORK_STATE         | reconnect logic     | no              |
| POST_NOTIFICATIONS (33+)     | message wake only   | yes (Android 13+)|
| CAMERA                       | attachments (switched off) | never asked |
| RECORD_AUDIO                 | voice messages, calls (not in the app) | never asked |
| READ_MEDIA_IMAGES/VIDEO/AUDIO (33+) | attachments (switched off) | never asked |
| USE_BIOMETRIC                | app lock            | no (per-use)    |

No `READ_CONTACTS`, no `ACCESS_FINE_LOCATION`, no `QUERY_ALL_PACKAGES`.

Sending attachments is switched off in the mobile app (`kAttachmentsEnabled`
in `apps/mobile/lib/src/features/attachments/attachments_feature.dart`), and
the app has no voice messages or calls, so nothing in the build asks for the
camera, the microphone or the media library at runtime. The
manifest still declares those permissions. Remove them (and the matching
usage strings in `ios/Runner/Info.plist`) before submitting a build that
ships without those features: a store reviewer reads a declared permission
as a feature.

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
Veil is an end-to-end encrypted messenger. Reviewers do not need a real
phone number or email. Use the following test handle:

  Handle: @playstore-review-<random>
  Transfer code: <generated per review>

Veil uses end-to-end encryption; the server cannot read user content, so
the review team cannot inspect message bodies. The Privacy Policy explains
this.
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
