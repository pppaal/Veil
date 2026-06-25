# VEIL — App Store Screenshot Specification

This document defines the screenshots required to submit **VEIL Messenger**
to the Apple App Store, the exact device sizes and pixel dimensions Apple
requires in 2025/2026, the per-locale shot list mapped to VEIL's real
features, and the localization and capture constraints.

VEIL on iOS is an **iPhone-only Flutter app** (`apps/mobile`, iOS deployment
target 14.0). There is no iPad-optimized build, so iPad screenshots are
**not required and should not be supplied** (see "Device scope" below).

---

## 1. Device scope

| Apple device class | Required for VEIL? | Reason |
|---|---|---|
| iPhone 6.9" display | **Yes — mandatory** | Primary required iPhone size in App Store Connect (2025/2026). |
| iPhone 6.5" display | **Yes — fallback set** | Covers older large-display devices; supply if not relying on Apple's automatic up-scaling from 6.9". |
| iPhone 6.3" / 6.1" / 5.5" | Optional | App Store Connect can scale from the 6.9" set; supply only if pixel-perfect framing matters. |
| iPad 13" display | **No** | VEIL is iPhone-scope only; no iPad-optimized UI is shipped. Do not declare iPad support, so iPad screenshots are not requested. |

> **iOS-only / phone scope note:** VEIL's Flutter project builds an iPhone
> app and an Android app. It does **not** ship an iPad-optimized layout, so
> the App Store Connect submission must not declare iPad device support.
> When iPad is not supported, App Store Connect does not require (and will
> not show an upload slot for) the 13" iPad screenshot set. Only the iPhone
> sizes below apply.

---

## 2. Required pixel dimensions (2025/2026)

App Store Connect requires screenshots at the **native resolution** of a
representative device in each size class. Provide PNG or JPEG, RGB, no
alpha/transparency, no rounded corners, full-bleed (the screenshot must
fill the frame — no device-frame padding baked in unless intentional
marketing art that still meets the exact pixel size).

### iPhone 6.9" display — **mandatory**

Representative devices: iPhone 16 Pro Max / 15 Pro Max class.

| Orientation | Width × Height (px) |
|---|---|
| Portrait | **1290 × 2796** |
| Landscape | 2796 × 1290 |

VEIL is portrait-only in practice; supply **portrait 1290 × 2796**.

(App Store Connect also accepts the alternate 6.9" pixel size **1320 × 2868**
from the very newest Max-class hardware. Standardize on **1290 × 2796** for
VEIL — it is the broadly accepted 6.9" portrait size and avoids per-device
re-rendering.)

### iPhone 6.5" display — **fallback set**

Representative devices: iPhone 14 Plus / 11 Pro Max / XS Max class.

| Orientation | Width × Height (px) |
|---|---|
| Portrait | **1242 × 2688** |
| Landscape | 2688 × 1242 |

Supply **portrait 1242 × 2688**.

> If you choose to rely on Apple's automatic scaling, only the 6.9" set is
> strictly mandatory and App Store Connect will down-scale it to smaller
> classes. The 6.5" set is included here as an explicit fallback so older
> large-display users see correctly framed art rather than scaled art.

---

## 3. Count per locale

VEIL ships two App Store locales: **Korean (ko)** and **English (en)**.

- **Minimum:** 1 screenshot per size class per locale.
- **Maximum:** 10 screenshots per size class per locale.
- **Target for VEIL:** **6 screenshots** per size class per locale
  (the shot list in §4).

That means the full deliverable is:

| Locale | Size class | Screenshots |
|---|---|---|
| en | iPhone 6.9" (1290 × 2796) | 6 |
| en | iPhone 6.5" (1242 × 2688) | 6 |
| ko | iPhone 6.9" (1290 × 2796) | 6 |
| ko | iPhone 6.5" (1242 × 2688) | 6 |

**Total: 24 image files** (6 shots × 2 sizes × 2 locales).

If you rely on Apple up-scaling from the 6.9" set only, the deliverable is
6 shots × 1 size × 2 locales = **12 image files**, plus the 6.5" set as an
optional quality upgrade.

---

## 4. Recommended shot list

Six screenshots, ordered for the App Store carousel. Each maps to a real,
shipped VEIL feature. The first 2–3 are the most important — they are what
most users see without scrolling.

| # | Screen | VEIL feature it shows | Caption intent (en) | Caption intent (ko) |
|---|---|---|---|---|
| 1 | **Onboarding / sign-up** | No phone number, no email, no real name. Device-bound identity. | "No phone number. No email. No recovery." | "전화번호도, 이메일도, 복구도 없이." |
| 2 | **Conversation list** | 1:1 and group conversations, presence, unread state. | "Your conversations live only on this device." | "대화는 이 기기에만 존재합니다." |
| 3 | **Encrypted chat with attachments** | E2EE message thread with image/voice/file attachments, typing indicator, optional read receipts. | "End-to-end encrypted. Servers never see plaintext." | "종단간 암호화. 서버는 평문을 볼 수 없습니다." |
| 4 | **Encrypted device transfer** | Atomic device transfer — old device must be alive; identity moves, never copied to a server. | "Move to a new phone — securely, with no cloud copy." | "클라우드 복사 없이 새 기기로 안전하게 이전." |
| 5 | **App lock** | Local app lock with PIN and biometrics (Face ID / Touch ID). | "Lock the app with a PIN or biometrics." | "PIN 또는 생체 인증으로 앱을 잠그세요." |
| 6 | **Settings / privacy posture** | No ads, no tracking, no third-party analytics; theme + language; the "no recovery" safety model. | "No ads. No tracking. By design." | "광고 없음. 추적 없음. 설계 원칙입니다." |

**Mapping notes (from VEIL's actual implementation):**

- Shots 1–3 must reflect the iOS Flutter app (`apps/mobile`), not the web
  demo. Crypto on mobile is the full Double Ratchet (X25519 + HKDF-SHA256 +
  AES-256-GCM, Ed25519 device signatures).
- Shot 3: attachments include image, voice, and generic file messages.
  Keep any visible message text generic and safe.
- Shot 4 (device transfer): show the transfer flow as a deliberate,
  old-device-present action. **Do not** imply backup or recovery — VEIL has
  none, and that is the product. Misleading "restore/backup" framing risks
  App Review rejection and contradicts the metadata.
- Shot 5 (app lock): demonstrate PIN entry and/or the biometric prompt.
- Shot 6: emphasize the privacy posture already declared in
  `metadata-en.txt` / `metadata-ko.txt` and `app-privacy-answers.md`.

---

## 5. Localization notes

- **Locales:** Korean (`ko`) and English (`en`) only. The mobile UI ships
  Korean and English; do **not** create a Japanese (`ja`) screenshot set —
  `ja` exists only in the web demo i18n, not as an App Store locale.
- **Capture per locale:** Re-capture each shot with the app's UI language
  set to match the target locale. Do not localize by overlaying translated
  text onto an English UI screenshot — the in-app chrome (tab labels,
  buttons, settings rows) must be in the matching language.
- **Caption text on art:** If overlay captions/marketing text are used, they
  must be fully translated per locale and must not cover system status-bar
  elements or core UI.
- **Status bar:** Use a clean status bar (full signal, full battery, no
  active call banner). Prefer a consistent time across all shots (e.g.
  9:41) for visual consistency.
- **Content safety:** Use placeholder names and neutral sample messages.
  No real personal data, no real phone numbers (the app does not use phone
  numbers — do not show one anywhere), no offensive sample content.
- **Consistency:** Use the same demo accounts, avatar set, and theme
  (recommend dark theme to match VEIL's "cold, encrypted" brand) across
  both locales so the only difference is language.
- **Order parity:** Keep the 6-shot order identical across `ko` and `en`
  so the carousel narrative is the same in both stores.

---

## 6. Capture method — **Mac only**

iOS App Store screenshots at the exact required pixel dimensions must be
captured on a **Mac**, because iOS Simulator and Xcode are macOS-only:

1. Build and run the VEIL iOS app on the **iOS Simulator** in Xcode on a
   Mac (e.g. an iPhone 16 Pro Max simulator for the 6.9" set at
   1290 × 2796, and an iPhone 14 Plus / 11 Pro Max simulator for the 6.5"
   set at 1242 × 2688). The simulator renders at exact native resolution,
   so captures already match Apple's required pixel sizes.
2. Set the simulator's app language to `en`, capture all 6 shots, then
   switch to `ko` and capture all 6 again. (Simulator: Settings →
   General → Language & Region, or relaunch via Flutter with the locale
   set.)
3. Capture with **Simulator → File → Save Screen** (or `⌘S`), which writes
   a PNG at the device's native resolution — do not resize afterward.
4. Alternatively capture on a physical iPhone of the right display class,
   but this still requires a Mac + Xcode/Apple Configurator to manage
   builds and to verify pixel dimensions before upload to App Store
   Connect.

> **Why Mac-only:** Xcode, the iOS Simulator, and the Flutter iOS
> toolchain do not run on Windows or Linux. There is no supported way to
> produce correctly-sized iOS App Store screenshots off macOS. Plan the
> screenshot pass on a Mac as a hard prerequisite for submission.

---

## 7. Pre-upload checklist

- [ ] 6.9" portrait shots are exactly **1290 × 2796** px.
- [ ] 6.5" portrait shots are exactly **1242 × 2688** px.
- [ ] 6 shots each for `en` and `ko`, in identical order.
- [ ] UI language in each shot matches its locale (captured, not overlaid).
- [ ] No phone numbers, no real personal data, clean status bar.
- [ ] Device-transfer shot does not imply backup/recovery.
- [ ] PNG/JPEG, RGB, no alpha, no rounded corners, full native resolution.
- [ ] iPad device support is **not** declared in App Store Connect; no iPad
      screenshots uploaded.
