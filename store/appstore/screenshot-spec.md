# App Store screenshot specification

This document defines the screenshots needed to submit **Veil Messenger**
to the Apple App Store: the device sizes and pixel dimensions Apple
requires in 2025/2026, the shot list mapped to what the app really does,
and how to capture them.

Veil on iOS is the Flutter app in `apps/mobile` (iOS deployment target
14.0). This spec plans the listing for iPhone alone, but the Xcode project
does not say so yet: it sets `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone and
iPad) in all three build configurations, so a build archived from it runs
on iPad, and App Store Connect then asks for iPad screenshots too (see
"Device scope" below).

---

## 1. Device scope

| Apple device class | Required for Veil? | Reason |
|---|---|---|
| iPhone 6.9" display | **Yes, mandatory** | Primary required iPhone size in App Store Connect (2025/2026). |
| iPhone 6.5" display | **Yes, fallback set** | Covers older large-display devices; supply if not relying on Apple's automatic up-scaling from 6.9". |
| iPhone 6.3" / 6.1" / 5.5" | Optional | App Store Connect can scale from the 6.9" set; supply only if pixel-perfect framing matters. |
| iPad 13" display | **Only if the build runs on iPad** | The project targets iPad today (`TARGETED_DEVICE_FAMILY = "1,2"`). Set the family to iPhone before archiving and no iPad set is needed; keep it and a 13" set is required. |

> **Device scope:** whether App Store Connect asks for iPad screenshots
> depends on the build you upload, not on a setting in App Store Connect:
> it asks for a 13" iPad set for any build that runs on iPad. This spec
> plans the listing for iPhone alone, so before archiving, set the Runner
> target's device family to iPhone (in Xcode: Runner target, General,
> Supported Destinations, remove iPad; the project then reads
> `TARGETED_DEVICE_FAMILY = 1`). If the family stays `"1,2"`, also capture
> the six shots on a 13" iPad simulator (portrait 2064 x 2752).

---

## 2. Required pixel dimensions (2025/2026)

App Store Connect requires screenshots at the **native resolution** of a
representative device in each size class. Provide PNG or JPEG, RGB, no
alpha/transparency, no rounded corners, full-bleed: the screenshot fills
the frame, with no device frame baked in.

### iPhone 6.9" display, mandatory

Representative devices: iPhone 16 Pro Max / 15 Pro Max class.

| Orientation | Width x Height (px) |
|---|---|
| Portrait | **1290 x 2796** |
| Landscape | 2796 x 1290 |

Veil is portrait-only in practice; supply **portrait 1290 x 2796**.

(App Store Connect also accepts the alternate 6.9" pixel size **1320 x 2868**
from the newest Max-class hardware. Standardize on **1290 x 2796**: it is
the broadly accepted 6.9" portrait size and avoids per-device re-rendering.)

### iPhone 6.5" display, fallback set

Representative devices: iPhone 14 Plus / 11 Pro Max / XS Max class.

| Orientation | Width x Height (px) |
|---|---|
| Portrait | **1242 x 2688** |
| Landscape | 2688 x 1242 |

Supply **portrait 1242 x 2688**.

> If you choose to rely on Apple's automatic scaling, only the 6.9" set is
> strictly mandatory and App Store Connect will down-scale it to smaller
> classes. The 6.5" set is included here as an explicit fallback so older
> large-display users see correctly framed screens rather than scaled ones.

---

## 3. Count

The app and the listing are English only, so there is one App Store locale:
**English (en)**.

- **Minimum:** 1 screenshot per size class.
- **Maximum:** 10 screenshots per size class.
- **Target for Veil:** **6 screenshots** per size class (the shot list in §4).

| Locale | Size class | Screenshots |
|---|---|---|
| en | iPhone 6.9" (1290 x 2796) | 6 |
| en | iPhone 6.5" (1242 x 2688) | 6 |

**Total: 12 image files** (6 shots x 2 sizes). If you rely on Apple
up-scaling from the 6.9" set only, the deliverable is **6 image files**,
plus the 6.5" set as an optional quality upgrade. A build that still runs
on iPad needs 6 more: the 13" iPad set (§1).

---

## 4. Shot list

Six screenshots, in carousel order. Each shows a real screen of the shipped
app. The first two or three matter most: they are what most people see
without scrolling.

| # | Screen | What it shows | Caption (if any) |
|---|---|---|---|
| 1 | **Choose a handle** | Sign-up with a handle: no phone number, no email, no real name. | "Sign up with a handle, not a phone number." |
| 2 | **Chats** | One-to-one and group chats. | "Only you and the people you talk to can read your chats." |
| 3 | **A chat** | Message thread with reactions, a disappearing-message timer, typing indicator, optional read receipts. | "Messages are end-to-end encrypted. The server never sees them in plaintext." |
| 4 | **Move to a new phone** | The old phone must be there and approve; the handle moves to keys made on the new phone, the old phone is signed out, and message history does not move. | "Move your handle to a new phone. The old one signs out." |
| 5 | **App lock** | Local app lock with a PIN and biometrics (Face ID / Touch ID). | "Lock the app with a PIN or biometrics." |
| 6 | **Settings** | Appearance, privacy switches, the Security group and its footer. | "No ads and no tracking." |

Notes:

- Shots 1 to 3 come from the iOS Flutter app (`apps/mobile`), not the web
  demo. Crypto on mobile is the full Double Ratchet (X25519 + HKDF-SHA256 +
  AES-256-GCM, Ed25519 device signatures).
- Shot 2: the Chats list shows no unread count (the app does not keep
  one), so the shot has none. Leave out chats whose last message is a voice
  note or a photo: the app cannot send either.
- Shot 3: text messages only. Sending attachments is switched off in the
  mobile app, and it has no voice messages or calls, so the shot shows none
  of them. Keep any visible message text ordinary and safe.
- Shot 4 (Move to a new phone): show the transfer as an action taken with
  the old phone present. **Do not** imply backup or recovery: Veil has
  neither. Misleading "restore/backup" framing risks App Review rejection
  and contradicts the metadata.
- Shot 5 (App lock): show PIN entry or the biometric prompt.
- Shot 6: show what `metadata-en.txt` and `app-privacy-answers.md` already
  declare; add no claim of its own.

---

## 5. Content and consistency

- **Language:** English only. Do not create screenshot sets for other
  locales; the app has no other language.
- **Captions:** optional. If used, one plain sentence above the screen,
  never covering the status bar or core UI. No gradients, no device
  mock-ups, no badges or pills on the art.
- **Status bar:** clean (full signal, full battery, no active call banner),
  with the same time on every shot (for example 9:41).
- **Content safety:** use the demo names the layout gate uses (Alex Kim,
  Sam Rivera, Priya Nair, Jonas Weber, Mia Chen) and neutral sample
  messages. No real personal data and no phone numbers anywhere (the app
  does not use them).
- **Consistency:** same demo accounts, same avatars and one theme (light or
  dark) for the whole set. The Google Play set is light: match its
  accounts, messages and theme
  ([`../play/screenshots/`](../play/screenshots/README.md)). Its status
  bar strip is blank because a test draws it; the iPhone captures keep the
  clean status bar described above.

---

## 6. Capture method: Mac only

The iPhone set is captured, not rendered. The Google Play set is drawn by a
Flutter test from the app's screens
([`../play/screenshots/README.md`](../play/screenshots/README.md)), but that
does not work for iOS: the app draws the platform's font, which on iOS is
SF Pro, and the test renderer does not have SF Pro. A rendered iPhone shot
would show Roboto, which no iPhone shows.

iOS App Store screenshots at the exact required pixel dimensions must be
captured on a **Mac**, because the iOS Simulator and Xcode are macOS-only:

1. Build and run the Veil iOS app on the **iOS Simulator** in Xcode on a
   Mac (for example an iPhone 16 Pro Max simulator for the 6.9" set at
   1290 x 2796, and an iPhone 14 Plus / 11 Pro Max simulator for the 6.5"
   set at 1242 x 2688; an iPad Pro 13-inch simulator for the iPad set at
   2064 x 2752, if the build still runs on iPad). The simulator renders at
   native resolution, so captures already match Apple's required pixel
   sizes.
2. Capture all 6 shots with **Simulator > File > Save Screen** (or `⌘S`),
   which writes a PNG at the device's native resolution. Do not resize
   afterward.
3. Alternatively capture on a physical iPhone of the right display class,
   but this still requires a Mac with Xcode or Apple Configurator to manage
   builds and to verify pixel dimensions before upload to App Store Connect.

> **Why Mac only:** Xcode, the iOS Simulator and the Flutter iOS toolchain
> do not run on Windows or Linux. There is no supported way to produce
> correctly sized iOS App Store screenshots off macOS. Plan the screenshot
> pass on a Mac as a hard prerequisite for submission.

---

## 7. Pre-upload checklist

- [ ] 6.9" portrait shots are exactly **1290 x 2796** px.
- [ ] 6.5" portrait shots are exactly **1242 x 2688** px.
- [ ] 6 shots, in the order of §4.
- [ ] No phone numbers, no real personal data, clean status bar.
- [ ] Device-transfer shot does not imply backup/recovery.
- [ ] PNG/JPEG, RGB, no alpha, no rounded corners, full native resolution.
- [ ] The archived build's device family is iPhone alone
      (`TARGETED_DEVICE_FAMILY = 1`), or a 13" iPad set is uploaded too.
