# VEIL — App Store Submission Checklist

A step-by-step, executable checklist for shipping VEIL Messenger to the iOS App Store.
Audience: an operator with a **Mac running Xcode** and an **Apple Developer Program account**.

Bundle id: `io.veil.mobile` · Flutter project: `apps/mobile` · Listing package: `store/appstore`

---

## ⛔ Ship-gate notice (read first)

VEIL declares an org-wide non-negotiable: **production must not ship until an external
cryptographer has audited the `LibCryptoAdapter`** (Double Ratchet over X25519 + AES-256-GCM
+ Ed25519 + HKDF-SHA256).

- Gate flag: `VEIL_AUDITED_CRYPTO_ATTESTED` (`.env.prod.example:42`, currently `false`).
- The production API **refuses to boot** while it is `false`
  (`apps/api/src/common/config/app-config.service.ts:129-140`).

Steps below are tagged:

- **[GATE-BLOCKED]** — do **not** perform until `VEIL_AUDITED_CRYPTO_ATTESTED=true` after a
  clean external audit retest. These are the public-distribution / production-pointing steps.
- **[GATE-OK]** — safe to do now; preparation, internal/TestFlight wiring against a non-prod
  backend, and all in-repo edits.

You **can** build, sign, and push internal **TestFlight** builds before the audit clears (pointed
at a staging/non-production backend). You **cannot** ship to the public App Store, nor point a
build at the production API, until the gate flips.

---

## Pre-flight: in-repo fixes to land before any upload (do these first)

These are code-today edits in `apps/mobile/ios` and `store/appstore`. None need a Mac, and they
prevent guaranteed TestFlight/Store rejections or stalls. **[GATE-OK]**

- [ ] **Remove the Cydia jailbreak probe.** Delete the `LSApplicationQueriesSchemes` array
      (the `cydia` entry) from `apps/mobile/ios/Runner/Info.plist` (lines ~29-32). The README
      already claims it was removed; the plist still has it. Apple rejects jailbreak-probe schemes.
- [ ] **Add the export-compliance key.** Add to `apps/mobile/ios/Runner/Info.plist`:
      ```xml
      <key>ITSAppUsesNonExemptEncryption</key>
      <true/>
      ```
      VEIL ships its own E2E crypto (not OS-only / not HTTPS-only), so the truthful value is
      **YES/true**. This suppresses the per-build export prompt; the *exemption* is claimed via
      the App Store Connect answers + BIS self-classification report (Step 12), **not** via this
      boolean. Do **not** add `ITSEncryptionExportComplianceCode` and do **not** file a CCATS —
      VEIL uses only standard published algorithms, so no CCATS/ERN is required.
- [ ] **Fix the EN subtitle (30-char limit).** `store/appstore/metadata-en.txt` subtitle
      "End-to-end encrypted privacy messenger" is 38 chars. Rewrite to ≤30, e.g.
      "Encrypted privacy messenger" (27) or "E2E encrypted private chat" (26). KO subtitle is fine.
- [ ] **(Optional, cosmetic) Align CFBundleURLName.** `Info.plist` `CFBundleURLName` is
      `app.veil.messenger` but the bundle id is `io.veil.mobile`. Align or leave; not a blocker.
- [ ] **Author the two missing source docs** referenced by this checklist (they do not exist yet):
      - `store/appstore/screenshot-spec.md` — required device sizes, per-screen shot list, captions.
      - `store/appstore/app-review-notes.md` — the no-account / no-recovery reviewer guide
        (draft content suggested inline in Step 13 below).

---

## 1. Apple Developer Program enrollment  · owner: human-account

- [ ] Enroll in the **Apple Developer Program** ($99/yr) at developer.apple.com — individual or
      organization. Org enrollment needs a D-U-N-S number and legal-entity verification (can take days).
- [ ] Note your **Team ID** (Membership page). You'll need it for `DEVELOPMENT_TEAM` and
      `ExportOptions.plist`.
- [ ] Sign the latest Program License Agreement and any pending agreements in App Store Connect
      (Agreements, Tax, and Banking) — **Paid/Free apps agreement must be Active** or the app
      cannot be submitted.

## 2. Register App ID + bundle id  · owner: human-account

- [ ] In **Certificates, Identifiers & Profiles → Identifiers**, register an App ID for
      **`io.veil.mobile`** (explicit, not wildcard).
- [ ] Enable required capabilities on the App ID:
      - **Push Notifications** — only if you intend real APNs (see note). Otherwise leave off.
      - (No other special capabilities are required by the current build.)
- [ ] **Push note:** Push/APNs is **not** a launch blocker for the private beta — delivery is
      disabled (`VEIL_PUSH_PROVIDER=none`) and no `aps` entitlement is wired. If you do want push,
      you must additionally create a `Runner/Runner.entitlements` with `aps-environment`, wire
      `CODE_SIGN_ENTITLEMENTS` into the build configs, and create an APNs Auth Key. Skip for beta.

## 3. Certificates + provisioning  · owner: mac-only

- [ ] Easiest path: in Xcode, open `apps/mobile/ios/Runner.xcworkspace` → Runner target →
      **Signing & Capabilities** → enable **Automatically manage signing** → select your Team.
      Xcode creates the **Apple Distribution** certificate + App Store provisioning profile.
- [ ] This also fixes the repo placeholders: `project.pbxproj` currently has **no**
      `DEVELOPMENT_TEAM`, no `CODE_SIGN_STYLE` on the Runner target, and `CODE_SIGN_IDENTITY` is the
      stale `iPhone Developer`. Set `DEVELOPMENT_TEAM` to your Team ID; let Xcode manage the identity.
- [ ] First-build bootstrap on the Mac (the project has never been built — no `Generated.xcconfig`,
      no `Pods/`):
      ```bash
      cd apps/mobile
      flutter pub get
      cd ios && pod install && cd ..
      flutter build ios --config-only
      ```

## 4. Create the App Store Connect app record  · owner: human-account

- [ ] In **App Store Connect → Apps → +** → New App:
      - Platform: iOS
      - Name: **VEIL Messenger** (must be globally unique on the Store)
      - Primary language: English (U.S.)
      - Bundle ID: **`io.veil.mobile`**
      - SKU: e.g. `veil-mobile-ios`
- [ ] Set **Primary category: Social Networking**, **Secondary: Utilities** (or Productivity).
- [ ] Add Korean (한국어) as an additional App Store localization so KO metadata can be entered.

## 5. Set version + build number  · owner: code-today

- [ ] Version/build come from Flutter `pubspec.yaml` `version: 0.1.0+1`
      (→ `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`).
- [ ] **Bump the build number for every upload** — App Store Connect rejects duplicate build
      numbers. Increment the `+N` (e.g. `0.1.0+2`) before each archive when iterating.

## 6. Archive + upload  · owner: mac-only

Choose Xcode **or** fastlane.

**Xcode path:**
- [ ] `flutter build ipa` (produces `build/ios/archive/Runner.xcarchive` and an `.ipa` under
      `build/ios/ipa/` using an auto-generated export). Or open `Runner.xcworkspace`,
      select **Any iOS Device (arm64)**, **Product → Archive**.
- [ ] In the Organizer, **Distribute App → App Store Connect → Upload**.

**fastlane / CI path (needs an `ExportOptions.plist` — none exists in repo yet):**
- [ ] Create `apps/mobile/ios/ExportOptions.plist` with `method = app-store-connect`, your
      `teamID`, and signing style. (No `Fastfile`/iOS CI lane exists today — `.github/workflows/ci.yml`
      is the API/mobile-analyze pipeline only. Authoring a Fastfile is optional.)
- [ ] `xcodebuild -exportArchive -archivePath Runner.xcarchive -exportOptionsPlist ExportOptions.plist
      -exportPath build/ipa`, then upload via `xcrun altool`/`xcrun notarytool`-era Transporter or
      `fastlane pilot upload`.
- [ ] **[GATE-BLOCKED]** Any build intended to point at the **production** API (and therefore any
      build promoted out of internal testing toward release) must wait for the audit gate. Internal
      TestFlight builds against a **staging/non-prod** backend are fine before the gate.

## 7. TestFlight beta  · owner: human-account / mac-only

- [ ] Wait for the uploaded build to finish **processing** in App Store Connect → TestFlight.
- [ ] Complete the **per-build export-compliance** answer if prompted (the `ITSAppUsesNonExemptEncryption`
      key from Pre-flight should suppress the prompt; if asked, answer per Step 12).
- [ ] **Internal testing:** add internal testers (up to 100, your team). No App Review needed.
      **[GATE-OK]** against a non-production backend.
- [ ] **External testing:** external groups require a **Beta App Review**. Provide beta test
      information + the review notes from Step 13. **[GATE-BLOCKED]** if the build points at
      production or is a release-candidate gated on the audit.

## 8. Fill metadata  · owner: human-account (text drafted code-today)

Transcribe from `store/appstore/metadata-en.txt` (English) and `store/appstore/metadata-ko.txt`
(Korean) into App Store Connect → the version's **App Information** / localized fields:

- [ ] Name, Subtitle (**use the corrected ≤30-char EN subtitle from Pre-flight**), Promotional Text,
      Description, Keywords (EN 69 / KO 36 chars — both under the 100 limit).
- [ ] Support URL `https://veil.app/support`, Marketing URL `https://veil.app`,
      Privacy Policy URL `https://veil.app/privacy`.
- [ ] **Verify all three URLs resolve to live pages before submission** — a dead support/privacy
      URL is a common rejection.

## 9. Screenshots  · owner: mac-only (spec drafted code-today)

- [ ] Author `store/appstore/screenshot-spec.md` if missing (see Pre-flight). It should enumerate:
      - **6.9" iPhone** screenshots (required for 2025/2026 submissions; the 6.5" set is still
        accepted/auto-scaled).
      - **13" iPad** screenshots **only if** `TARGETED_DEVICE_FAMILY` keeps iPad (currently `1,2`
        = iPhone + iPad). Decide whether iPad is actually supported; if not, drop iPad from the
        family and skip iPad shots.
      - Per-screen shot list + captions (onboarding/identity creation, 1:1 chat, group chat,
        app-lock, device-transfer).
- [ ] Capture from the Simulator/device on the Mac, then upload to each localization.
- [ ] App preview video is **optional** — skip for beta.

## 10. App Privacy ("nutrition label")  · owner: human-account (answers drafted)

Transcribe `store/appstore/app-privacy-answers.md` into App Store Connect → **App Privacy**:

- [ ] Data collected: **User ID** (linked, App Functionality, not tracking), **Device ID**
      (linked, App Functionality, not tracking), **User Content / encrypted payloads**
      (NOT linked — server holds only ciphertext, App Functionality, not tracking),
      **Crash Data** (opt-in Sentry, NOT linked, App Functionality, not tracking).
- [ ] **Tracking: No.** Mark the long "Data Not Collected" list accordingly.

## 11. Content rights  · owner: human-account

- [ ] Answer the **Content Rights** question: **"No, it does not contain third-party content."**
      (User-generated encrypted messages are first-party UGC.)

## 12. Export compliance  · owner: human-account (+ external filings)

In App Store Connect export-compliance flow (or at TestFlight upload):

- [ ] "Does your app use encryption?" → **Yes**.
- [ ] "Does it qualify for any exemptions in Category 5, Part 2?" → **Yes**.
- [ ] Select the **standard/published-algorithms mass-market self-classification** exemption
      (15 CFR 740.17(b)(1)) — **NOT** "only HTTPS/OS-provided" and **NOT** "proprietary algorithm".
- [ ] When asked whether a year-end **self-classification report** has been filed, answer truthfully.
- [ ] **No CCATS/ERN** and **no `ITSEncryptionExportComplianceCode`** are needed (standard algorithms).
- [ ] **External filings (owner: external/legal, recurring):**
      - File the **annual BIS self-classification report** (ECCN 5D992.c) to `crypt@bis.doc.gov`
        and `enc@nsa.gov`, before/at first export and annually by **Feb 1**.
      - If distributing in **France**, prepare and upload the **French/ANSSI encryption declaration**
        (~1 month processing — start early). If you geo-restrict France out, this is not needed.

## 13. Review notes  · owner: code-today (draft) → human-account (paste)

- [ ] Author `store/appstore/app-review-notes.md` if missing, then paste into the version's
      **App Review Information → Notes**. **Critical** because VEIL has no accounts, no phone number,
      and no recovery, so reviewers cannot "log in." The notes must explain:
      - No demo credentials are needed and none exist — there is **no login**.
      - How an identity is created on **first launch** (device-bound, no account/phone/email).
      - How to test **1:1 and group messaging** using **two devices/simulators** (you exchange
        the on-screen identity to start a conversation).
      - That **no account recovery exists by design** (losing the device loses the chats).
      - The **opt-in Sentry crash toggle** (off by default).
      - Contact: `privacy@veil.app`.
- [ ] Provide an App Review **contact name + phone + email**.

## 14. Age rating  · owner: human-account (draft answers ok)

- [ ] Complete the **Age Rating questionnaire** live in App Store Connect (2026 bands).
      Recommended posture: no objectionable content, but note **unrestricted messaging /
      user-generated content** — which typically pushes a messenger to **17+/18+**. Answer truthfully.

## 15. Submit for Review  · owner: human-account — **[GATE-BLOCKED]**

> **Do not perform Step 15 until `VEIL_AUDITED_CRYPTO_ATTESTED=true` after a clean external
> crypto audit retest.** Public App Store distribution is the org-wide ship gate.

- [ ] Confirm the gate: external audit complete, critical findings remediated + retested, closures
      recorded in `docs/external-review-remediation-tracker.md`, and `VEIL_AUDITED_CRYPTO_ATTESTED`
      flipped to `true` so the production API boots.
- [ ] Confirm the release build points at the **production** backend (now bootable).
- [ ] Final checks: build selected, all metadata/screenshots/privacy/export/age-rating/review-notes
      complete, agreements Active.
- [ ] Choose release option (manual / automatic / phased).
- [ ] Click **Add for Review → Submit for Review**.

---

## Quick owner legend

| Step | What | Owner | Audit gate |
|------|------|-------|-----------|
| Pre-flight | Info.plist + metadata fixes, author missing docs | code-today | GATE-OK |
| 1 | Developer enrollment | human-account | GATE-OK |
| 2 | App ID / bundle id | human-account | GATE-OK |
| 3 | Certs + provisioning + first build | mac-only | GATE-OK |
| 4 | App Store Connect record | human-account | GATE-OK |
| 5 | Version/build number | code-today | GATE-OK |
| 6 | Archive + upload | mac-only | GATE-BLOCKED for prod-pointing/release builds |
| 7 | TestFlight | human-account/mac-only | GATE-OK internal (staging); GATE-BLOCKED external/release |
| 8 | Metadata | human-account | GATE-OK |
| 9 | Screenshots | mac-only | GATE-OK |
| 10 | App Privacy | human-account | GATE-OK |
| 11 | Content rights | human-account | GATE-OK |
| 12 | Export compliance (+BIS/ANSSI) | human-account/external | GATE-OK |
| 13 | Review notes | code-today → human-account | GATE-OK |
| 14 | Age rating | human-account | GATE-OK |
| 15 | **Submit for Review** | human-account | **GATE-BLOCKED** |
