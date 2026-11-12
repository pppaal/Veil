# VEIL Mobile

Flutter mobile shell for the VEIL MVP. This source tree is scaffolded manually in this environment because the Flutter SDK is not installed here.

After installing Flutter locally:

1. Run `flutter pub get`
2. Run `dart run build_runner build --delete-conflicting-outputs`
3. Start the API locally from the repo root with `pnpm dev:api`
4. Run Flutter with API defines, for example:

```bash
flutter run \
  --dart-define=VEIL_API_BASE_URL=http://10.0.2.2:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://10.0.2.2:3000
```

## Release builds

A release build must name its relay and pin its TLS keys. With the
development defaults (a localhost endpoint, or no `VEIL_TLS_PINS`) a release
build stops at the configuration-error screen and the security status screen
reports it as blocked (`VeilConfig.validateRuntimeConfiguration`). `VEIL_ENV`
is an API server variable; the app ignores it.

```bash
flutter build appbundle --release \
  --dart-define=VEIL_API_BASE_URL=https://api.example.org/v1 \
  --dart-define=VEIL_REALTIME_URL=https://api.example.org \
  --dart-define=VEIL_TLS_PINS=spki:<current>,spki:<next> \
  --dart-define=VEIL_OBJECT_STORAGE_HOSTS=<bucket host> \
  --dart-define=VEIL_OBJECT_STORAGE_PINS=spki:<bucket pin>
```

The realtime client appends `/v1/realtime` itself. Pin format and rotation
are described at the top of `lib/src/core/network/pinned_http_client.dart`;
ship the next pin before rotating.

## libsignal bridge (opt-in, never built yet)

Default Android and iOS builds leave the native libsignal bridge and Signal's
native libraries out; the Dart libsignal adapter then reports the bridge as
unavailable. To build it in:

- Android: `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal --android-project-arg=veil.libsignal=true`
  (compiles `android/app/src/libsignal` and adds `org.signal:libsignal-android`).
- iOS: add `Runner/Crypto/VeilCryptoBridge.swift` and the LibSignalClient
  package to the Runner target, register `VeilCryptoBridgePlugin` in
  `AppDelegate.swift` (see the comment there), and build Dart with
  `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`.

The Kotlin bridge type-checks against libsignal-client 0.86.5; neither bridge
has been built into an app on a real toolchain or run.

Current mobile wiring includes:

- register -> challenge -> verify -> session persistence
- direct conversation create/list and encrypted envelope send/list
- upload-ticket/complete attachment send scaffold
- download-ticket resolution scaffold for encrypted attachments
- websocket conversation sync
- local PIN/biometric app lock hooks
- device transfer init/approve/complete scaffold
- Drift-backed cache service scaffold pending codegen

Crypto status: the runtime adapter (`createConfiguredCryptoAdapter` in
`lib/src/core/crypto/crypto_adapter_registry.dart`) wires the real
`LibCryptoAdapter` (X25519 ECDH + HKDF-SHA256 + AES-256-GCM). The
`MockCryptoAdapter` is retained for unit tests only and is never used at
runtime. Production builds are still gated behind the
`VEIL_AUDITED_CRYPTO_ATTESTED` define until an external crypto audit
clears the engine.
