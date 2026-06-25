# VEIL — Go-live today (Google Play internal testing)

A copy-paste path to get the app into testers' hands **today** via Play's
**Internal testing** track. Public/production launch is gated separately —
see the note at the bottom.

All commands run from `apps/mobile/` unless stated. Replace `puro flutter`
with plain `flutter` if you don't use puro.

---

## 1. Generate the upload keystore (once)

```bash
keytool -genkeypair -v \
  -keystore veil-upload.jks \
  -keyalg RSA -keysize 4096 -validity 36500 \
  -alias veil
```

Store `veil-upload.jks` somewhere safe and **outside the repo**. If you lose
it you can recover via Play App Signing, but keep a backup anyway.

## 2. Point the build at it

```bash
cp apps/mobile/android/keystore.properties.example \
   apps/mobile/android/keystore.properties
```

Edit `apps/mobile/android/keystore.properties`:

```properties
storeFile=/absolute/path/to/veil-upload.jks
storePassword=********
keyAlias=veil
keyPassword=********
```

`keystore.properties` is gitignored — it never gets committed. The release
build **fails loudly** if this file is missing (no silent debug-key
fallback).

## 3. Pre-flight + build the release bundle

```bash
cd apps/mobile
puro flutter gen-l10n
puro flutter analyze            # must be clean
puro flutter test               # must be green
puro flutter build appbundle --release --dart-define=VEIL_ENV=prod
```

> No `--flavor` — this project defines no product flavors.

Output: `apps/mobile/build/app/outputs/bundle/release/app-release.aab`

## 4. Play Console — internal testing track

1. Create a Google Play developer account ($25 one-time) if you don't have one.
   - Identity verification can take anywhere from minutes to a few days. This
     is the one step that may block "today" — start it first.
2. **Create app** → name "Veil", default language Korean, type "App", free.
3. **Testing → Internal testing → Create new release** → upload
   `app-release.aab`.
4. Add testers: create an email list (up to 100), save.
5. **Review release → Start rollout to Internal testing.** Internal releases
   go live with minimal review, usually within minutes to a few hours.
6. Copy the **join link**, send it to your testers. They opt in, then install
   from the Play Store like any app.

## 5. Required listing fields (can be minimal for internal testing)

- **Privacy policy URL** → `https://pppaal.github.io/Veil/`
  (enable Pages first — see `docs/privacy-policy-hosting.md`).
- **Data safety form** → mirror `store/appstore/app-privacy-answers.md`
  (User ID + Device ID, "App functionality", no tracking, no ads, no
  third-party analytics).
- **Content rating** questionnaire → Communication category.
- **App content** → target audience 14+, no ads.
- Store listing text → paste from `store/play/*-ko.txt` and `*-en.txt`.

---

## What "today" can and cannot mean

| Goal | Today? | Why |
| --- | --- | --- |
| Invited testers install & use it | ✅ Yes | Internal testing track, near-instant |
| Anyone searches Play and installs | ❌ No | New personal dev accounts must run **closed testing with ≥12 testers for 14 days** before production access, plus first-app review (a few days) |

So: ship to internal testers today; the public production listing follows
after the 14-day closed-testing gate. Use the same AAB and listing for both —
nothing here is throwaway.
