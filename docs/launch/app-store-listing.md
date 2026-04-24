# App Store Listing — Draft

Target storefront: Apple App Store (iOS, iPadOS, macOS Catalyst).
Bundle identifier: `app.veil.messenger` (placeholder; align with
`apps/mobile/ios/Runner.xcodeproj`).

> **Legal review required** for every user-facing string below before
> submission. This is a starting draft, not reviewed copy.

## App name

**Veil — Private Messenger**

Alternative (if name collision): **Veil Messenger**.

## Subtitle (30 chars)

`Messages that actually vanish`

## Promotional text (170 chars, updatable without review)

`End-to-end encrypted. No phone number. No cloud backup. No ads. Built for people who actually want their messages to stay private.`

## Description

Veil is an end-to-end encrypted messenger built around a single idea:
what you say on Veil never leaves your device in a form the server can
read.

- **Ciphertext-only relay.** The server routes encrypted envelopes. It
  does not see message bodies, attachments, or conversation content.
- **No phone number.** No SMS verification, no address-book upload, no
  contact discovery. You choose a handle and share it on your terms.
- **Device-bound identity.** Your identity lives on your device. There is
  no cloud copy. When you retire a device, its access retires with it.
- **Disappearing messages.** Set a per-conversation timer and messages
  self-destruct on every device after it expires. Or send a view-once
  message that is hard-deleted the moment it's read.
- **Safety, quietly.** Block, mute, or report without the other side
  seeing the block as a visible state.
- **Signed backups.** Your local history can be sealed under a passphrase
  you control. No cloud, no recovery you didn't consent to.

Veil does not run ads, does not sell analytics, and does not offer account
recovery. Losing your device is final by design — that's the privacy
guarantee.

## Keywords (100 chars, comma-separated)

`private,messenger,encrypted,chat,privacy,secure,no sms,no phone,signal,e2ee,disappearing`

## Category

- Primary: **Social Networking**
- Secondary: **Productivity**

## Age rating

17+ (unrestricted web access not enabled, but user-generated content is
end-to-end encrypted so we cannot moderate private content — this is the
honest rating even though we ship a reporting path).

## Privacy nutrition label

### Data Not Collected

This is the truth for Veil. Every category below maps to "Data Not
Collected" in App Store Connect's privacy questionnaire, assuming the
crash reporter is off or configured as "Not linked to identity."

- Contact Info — not collected
- Health & Fitness — not collected
- Financial Info — not collected
- Location — not collected
- Sensitive Info — not collected
- Contacts — not collected (no address-book sync by design)
- User Content — encrypted on the user's device; the server never has
  access to plaintext, therefore not "collected" per Apple's definition
- Browsing History — not collected
- Search History — not collected
- Identifiers — **handle only**, no IDFA, no IDFV linked to identity
- Purchases — not collected
- Usage Data — not collected (no analytics SDK)
- Diagnostics — crash logs only, not linked to identity, user-togglable

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

1. Hero shot — conversation list with at least one disappearing-messages
   indicator visible. Korean + English variants.
2. Safety numbers screen — the "verify this conversation" moment.
3. Compose + view-once toggle.
4. Settings → Block list + Mute list.
5. Onboarding — "no phone number required" screen.

Asset directory: `apps/mobile/ios/fastlane/screenshots/` (not yet
configured — see `docs/launch/store-asset-pipeline.md` once it exists).

## Review notes for Apple

Paste the following block into "App Review Information → Notes":

```
Veil is an end-to-end encrypted messenger. To sign in, the reviewer can
use the following test account:

  Handle: @appstore-review-<random>
  Device transfer token: <generated per review, see README>

Veil does not use a phone number or email for onboarding. The reviewer
chooses a handle, and the app generates keys on-device. There is no
cloud account.

Because Veil is end-to-end encrypted, the server cannot display message
content to the review team. Test messages sent between the reviewer's
two installs will be visible only on those installs.
```

## Export compliance

Veil uses end-to-end encryption. For App Store submission:

- `ITSAppUsesNonExemptEncryption` = `YES`
- `ITSEncryptionExportComplianceCode` = <issued BIS CCATS / ERN>
- Submission requires a BIS annual self-classification report (CCATS or
  ERN — coordinate with legal; Signal files under ERN).

If export compliance isn't filed, submission will be rejected.

## Localization

Priority v1: English, Korean. Both privacy policies exist in-repo. Tier 2
after launch: Japanese, Chinese (Traditional), German.

## Submission checklist

- [ ] Privacy policy URL responds with 200
- [ ] All test accounts work
- [ ] Export compliance CCATS/ERN filed
- [ ] Age rating questionnaire answered honestly (17+)
- [ ] No placeholders in Promotional text / Description
- [ ] Screenshots exist for every required device class
- [ ] Legal has reviewed "description" + "promotional text"
- [ ] `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`,
      `NSPhotoLibraryUsageDescription` copy reviewed and matches actual
      feature behavior
- [ ] Push entitlement only if push is actually wired to APNs for this
      build (otherwise reject-risk)
- [ ] Crash reporter settings reviewed against privacy nutrition label
