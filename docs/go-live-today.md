# VEIL — Go-live today (Google Play internal testing)

A copy-paste path to get the app into the hands of testers you invite
**today** via Play's **Internal testing** track. Internal and closed testing
are for invited testers only. A public/production launch waits for the
external crypto audit — see the note at the bottom.

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
puro flutter build appbundle --release \
  --dart-define=VEIL_API_BASE_URL=https://<relay>/v1 \
  --dart-define=VEIL_REALTIME_URL=https://<relay> \
  --dart-define=VEIL_TLS_PINS=<pins> \
  --dart-define=VEIL_OBJECT_STORAGE_HOSTS=<object-store host> \
  --dart-define=VEIL_OBJECT_STORAGE_PINS=<pins>
```

> A release build refuses to run without a non-local relay URL and
> `VEIL_TLS_PINS`. The app ignores `VEIL_ENV`; passing it changes nothing.

> No `--flavor` — this project defines no product flavors.

Output: `apps/mobile/build/app/outputs/bundle/release/app-release.aab`

> **Not done yet: the first Android release build and the first iOS archive
> produced on a real toolchain.** Neither has ever been built: CI runs
> `flutter analyze` and `flutter test` only and builds no app. The first
> `appbundle` run above is also the first time the Android
> build files are exercised, so budget time for build fixes. Default builds
> leave out the libsignal bridge; it is opt-in
> (`docs/libsignal-migration-implementation.md`).

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
- **Data safety form** → transcribe `store/play/data-safety-answers.md` row
  for row. Data collected: User IDs, Device or other IDs (device ids and push
  tokens), Contacts (the in-app contact list, conversation membership and call
  records) and Other user-generated content (group and channel names and
  descriptions and device labels), plus messages and attachments held only as
  ciphertext; all "App functionality", not shared, no tracking, no ads, no
  third-party analytics.
- **Content rating** questionnaire → Communication category.
- **App content** → target audience 14+, no ads.
- Store listing text → paste from `store/play/*-ko.txt` and `*-en.txt`.

---

## What "today" can and cannot mean

| Goal | Today? | Why |
| --- | --- | --- |
| Invited testers install & use it | ✅ Yes | Internal testing track, near-instant |
| Anyone searches Play and installs | ❌ No | New personal dev accounts must run **closed testing with ≥12 testers for 14 days** before production access, plus first-app review (a few days) |

So: ship to invited internal testers today. The public production listing
waits for **both** Play's 14-day closed-testing gate **and** the external
crypto audit: the backend refuses to boot with `VEIL_ENV=production` until
`VEIL_AUDITED_CRYPTO_ATTESTED=true` and `VEIL_AUDIT_REPORT_SHA256` name the
signed report, and a public audience must not be served by a development-mode
backend. Use the same AAB and listing for both — nothing here is throwaway.
