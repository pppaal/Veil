# VEIL MVP Demo Runbook

This runbook is for the current repository state.

## Preconditions

- Docker installed
- Node.js and pnpm installed
- Flutter and Dart installed locally
- Android emulator or physical device available

## 1. Start infrastructure

```bash
pnpm install
pnpm docker:up
pnpm db:generate
pnpm dev:api
```

API defaults to `http://localhost:3000/v1`.

## 2. Start mobile in API mode

From a second terminal:

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run \
  --dart-define=VEIL_API_BASE_URL=http://10.0.2.2:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://10.0.2.2:3000
```

For iOS simulator, replace `10.0.2.2` with `localhost`.

## 3. Demo path

1. Open VEIL.
2. Accept the onboarding warning.
3. Create account A with a handle such as `icarus`.
4. Set a PIN when the app lock screen appears.
5. Open settings and note the bound device id.
6. Start a direct chat to another registered handle.
7. Send an opaque text message.
8. Open attachment preview and send an encrypted attachment placeholder.
9. Open security status and confirm no backup/no recovery messaging.
10. Open device transfer and run:
   - init transfer
   - import payload on the new device
   - register the new-device claim
   - approve that claim on the old device
   - complete transfer on the new device
11. Confirm the old device session is cleared after completion.
12. On a fresh bound session, open settings and test `Revoke this device`.
13. Confirm the app returns to account creation and the old bearer token no longer works.

## 4. Current demo limitations

- Crypto is mock-only.
- Attachment upload uses encrypted placeholder bytes.
- The new device side of transfer is scaffolded, not a separate running mobile instance.
- Push fallback is metadata-only and the real APNs/FCM provider is not wired.
- Drift cache requires local codegen before the app will compile.

## 5. Verification commands

```bash
pnpm build
pnpm lint
pnpm test
pnpm -C apps/api test:e2e
```
