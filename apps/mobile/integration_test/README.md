# VEIL mobile integration tests

Real-device / emulator scenarios that the unit + widget test pyramid
can't reach. The Flutter equivalent of Playwright.

## Status

Scaffold only. `auth_smoke_test.dart` is a placeholder that pumps a
trivial widget so the toolchain (Gradle + Xcode + build_runner) runs
without crashing. Real scenarios depend on a running API and a
connected device, neither of which we run in CI today.

## Run

```bash
cd apps/mobile

# Android emulator (Pixel 8 image recommended):
flutter test integration_test/ \
  --dart-define=VEIL_API_BASE_URL=http://10.0.2.2:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://10.0.2.2:3000

# iOS simulator (boot the simulator first):
flutter test integration_test/ \
  --dart-define=VEIL_API_BASE_URL=http://127.0.0.1:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://127.0.0.1:3000
```

## Scenarios to add

When a real-device QA pass starts, expand to cover:

1. **Auth happy path** — register → challenge → verify → token persisted
   in `flutter_secure_storage`
2. **Auth collision** — re-register existing handle returns `handle_taken`
3. **Session restore** — kill app, reopen, lands directly on chat list
4. **Send + receive** — Alice (test) → Bob (separate device or sim) round
   trip. Requires either two devices or a server-side recipient stub.
5. **Transfer flow** — old device init → new device claim with QR scan
   stubbed by test
6. **Logout** — drains secure storage, blocks subsequent API calls

## CI consideration

The current GitHub Actions runner does not boot Android emulator or iOS
simulator. Wiring this would require either:

- Self-hosted runner with `flutter test integration_test/` invoked
  through a real emulator
- Firebase Test Lab or AWS Device Farm (paid; deferred until production
  push notification setup is also funded)

Until then, integration_test runs only on the maintainer's local device
during the real-device QA pass documented in
`docs/real-device-performance-execution.md`.
