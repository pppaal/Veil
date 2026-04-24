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
- Encrypted local backups you seal under a passphrase you control.

**What Veil is not**
- Not ad-supported. Not analytics-monetized.
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

The Data Safety form in Play Console requires per-category disclosure.
Veil's honest answers:

| Category          | Collected? | Shared? | Purpose      | Optional? | Notes |
|-------------------|-----------|---------|--------------|-----------|-------|
| Name              | No        | —       | —            | —         | handle only, no real name |
| Email             | No        | —       | —            | —         | never asked |
| Phone number      | No        | —       | —            | —         | never asked |
| Physical address  | No        | —       | —            | —         | |
| User IDs          | Yes       | No      | Functionality| No        | server-generated userId + deviceId, never linked to PII we don't have |
| Contacts          | No        | —       | —            | —         | no address-book sync by design |
| Messages          | Yes — encrypted only | No | Functionality | No | server stores ciphertext envelopes, cannot decrypt |
| Photos/videos     | Yes — encrypted only | No | Functionality | No | same — attachment ciphertext only |
| Approximate location | No     | —       | —            | —         | |
| Precise location  | No        | —       | —            | —         | |
| Device/other IDs  | No        | —       | —            | —         | no IDFA/AAID collected |
| App activity / search | No    | —       | —            | —         | no analytics SDK |
| Web browsing      | No        | —       | —            | —         | |
| App info / perf   | Optional  | No      | App diagnostics | Yes    | crash logs only if user opts in |
| Financial         | No        | —       | —            | —         | |

**Data is encrypted in transit**: YES (TLS + app-layer E2EE).
**Users can request data deletion**: YES (in-app Delete Account).

Any deviation from this table is a launch blocker — amend this doc and
the Data Safety form together.

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
- [ ] Data Safety form matches the table above with no optimistic claims
- [ ] Content rating questionnaire answered honestly (UGC=yes, UGC
      encrypted=yes)
- [ ] Target API level meets Play's current requirement
- [ ] All permissions declared are actually used; nothing extra
- [ ] Store listing copy reviewed by legal
- [ ] Release track notes filed in `docs/launch/release-notes/`
- [ ] Closed testing pool has met Play Console's minimum-days-of-testing
      requirement (new personal-account requirement)
