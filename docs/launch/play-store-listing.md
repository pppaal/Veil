# Google Play Listing — Draft

Target storefront: Google Play.
Application ID: `app.veil.messenger` (placeholder; align with
`apps/mobile/android/app/build.gradle.kts`).

> **Legal review required** for every user-facing string below before
> publishing. This is a starting draft, not reviewed copy.

## App title (30 chars)

`Veil — Private Messenger`

## Short description (80 chars)

`End-to-end encrypted messenger. No phone number. Messages that actually vanish.`

## Full description

Veil is an end-to-end encrypted messenger. The server relays ciphertext
envelopes; it never sees the content of your messages.

**What Veil is**
- End-to-end encrypted messages and attachments. Server sees ciphertext.
- No phone number, no email, no address book upload. You pick a handle.
- Device-bound identity. No cloud account. No silent sync across devices
  you didn't explicitly add.
- Disappearing messages (per-conversation timer) and view-once messages
  (hard-deleted on first read, on every device).
- Block, mute, and report without leaking "I blocked you" as visible
  state to the other side.

**What Veil is not**
- Not ad-supported. Not analytics-monetized.
- No backups, local or cloud.
- No account recovery. Losing your device is final — that's the
  privacy guarantee.
- No contact discovery. No "who else is on Veil" directory.

**Who Veil is for**
People who want their private conversations to actually be private. If
"private" to you means "the company running the server can't read my
messages even if they try," Veil is for you.

## Category

- Primary: **Communication**

## Content rating

IARC rating questionnaire should be answered honestly:

- User-generated content: YES (we ship a messenger)
- Encrypted UGC not visible to the developer: YES
- In-app reporting: YES (abuse reports to a privileged queue)
- Interactive features: chat only; no live video to strangers, no
  unmoderated public rooms

Expected rating band: **Teen** (13+) — same band Signal sits in.

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
| CAMERA (feature-gated)       | attachments         | yes             |
| RECORD_AUDIO (feature-gated) | voice messages/calls| yes             |
| READ_MEDIA_IMAGES (33+)      | attachments         | yes             |
| USE_BIOMETRIC                | app lock            | no (per-use)    |
| FOREGROUND_SERVICE (calls)   | active call only    | declared        |

No `READ_CONTACTS`, no `ACCESS_FINE_LOCATION`, no `QUERY_ALL_PACKAGES`.

## Support & policy URLs

- Privacy Policy: `https://veil.app/privacy`
- Support: `https://veil.app/support`

## Screenshot set

Five screenshots, 16:9 landscape or 9:16 portrait. Same storyline as the
App Store screenshots — reuse assets.

## Google Play review notes

Paste into "App access" review form:

```
Veil is an end-to-end encrypted messenger. Reviewers do not need a real
phone number or email. Use the following test handle:

  Handle: @playstore-review-<random>
  Device transfer token: <generated per review>

Veil uses end-to-end encryption; the server cannot read user content, so
the review team cannot inspect message bodies. This is intentional and
documented in the Privacy Policy.
```

## Release track plan

1. **Internal testing** — closed to the dev org, use for every push
   during release hardening.
2. **Closed testing (alpha)** — opt-in tester pool, ~50 testers. At
   least 14 days before broader rollout.
3. **Closed testing (beta)** — 200–500 testers. Required for new
   personal-developer accounts per Play Console 2024 rules.
4. **Production** — staged rollout at 5% → 20% → 100% over 7 days.

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
