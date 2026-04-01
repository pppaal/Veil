# VEIL Internal Alpha Runbook

This runbook is for internal QA on the current VEIL mobile and API scaffold.

## Scope

Use this build to validate:

- onboarding clarity
- device-bound registration flow
- direct conversation creation
- encrypted-envelope chat flow
- attachment placeholder flow
- disappearing message UX
- app lock UX
- device transfer UX
- settings and security status coherence

Do not use this build as a production messenger.

## Preconditions

- Docker installed
- Node.js and pnpm installed
- Flutter and Dart installed locally
- Android emulator, iOS simulator, or Windows desktop runtime available

## 1. Start local services

```bash
pnpm install
pnpm docker:up
pnpm db:generate
pnpm dev:api
```

The API health endpoint should return:

```text
GET http://localhost:3000/v1/health
```

Expected response:

```json
{"status":"ok","service":"veil-api"}
```

For API-level smoke before opening the mobile client:

```bash
pnpm alpha:smoke
```

## 2. Start the mobile client

### Android emulator

```bash
cd apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run \
  --dart-define=VEIL_API_BASE_URL=http://10.0.2.2:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://10.0.2.2:3000
```

### Windows desktop sanity run

```bash
pnpm dev:mobile:desktop
```

Windows desktop requires Windows Developer Mode first.
For a concise click-by-click Windows flow, see [Internal Alpha Desktop QA](internal-alpha-desktop-qa.md).

## 3. Internal alpha flow

### A. Onboarding and account bind

1. Launch VEIL.
2. Confirm the splash screen routes into onboarding.
3. Read the warning screen and confirm the copy is explicit about no backup, no recovery, and no restore path.
4. Enter an optional display name.
5. Choose a handle and confirm the UI shows the bind phases:
   - generating local identity
   - registering handle
   - requesting challenge
   - verifying device
6. Confirm the app lands in the conversation list after verification.

### B. Conversation list and direct chat

1. Confirm the empty state is clear when no channels exist.
2. Use `Start direct chat`.
3. Enter another registered handle.
4. Confirm the direct conversation appears in the list.
5. Pull to refresh and confirm the list remains stable.

### C. Chat and disappearing messages

1. Open a direct channel.
2. Send a normal text message.
3. Turn disappearing messages on.
4. Send another message and confirm the bubble shows remaining time.
5. Wait for expiration and confirm the expired message disappears locally.

### D. Attachments

1. Open the attachment screen from the chat room.
2. Confirm the copy states opaque blob upload and encrypted envelope send.
3. Send the attachment placeholder.
4. Confirm the chat room renders an encrypted attachment card.
5. Resolve a download ticket and confirm the ticket dialog appears.

### E. App lock

1. Open Settings -> App lock.
2. Set a PIN if none exists.
3. Lock the app from Settings.
4. Confirm unlock works with PIN.
5. If biometrics are available, confirm biometric unlock works and failure copy is readable.

### F. Device transfer

1. On the old device, open Settings -> Device transfer.
2. Confirm the screen explicitly states that the old device is required.
3. Run init transfer.
4. Copy the transfer payload from the old device.
5. On the new device, open `Transfer from old device` from the account creation screen.
6. Paste the transfer payload and import it.
7. Register the new-device claim and note the claim code.
8. Return to the old device and approve that exact claim code.
9. Complete the transfer on the new device.
10. Confirm the new device lands in the authenticated session.
11. Confirm the old device session is cleared locally after completion.

### G. Security surfaces

1. Open Security Status.
2. Confirm it reflects:
   - current bound device state
   - local secret refs
   - app lock status
   - realtime relay state
   - local cache state
   - mock crypto warning
3. Open Settings.
4. Confirm revoke/logout copy does not imply recovery.

## 4. Failure cases to check

- Registration with an invalid or duplicate handle
- Starting a direct chat with an unknown handle
- Attachment send while the API is unavailable
- Unlock with a wrong PIN
- Transfer complete without init/approve
- Transfer complete on a new device with an invalid payload
- Revoke current device and confirm the session is cleared

## 5. Verification commands

```bash
pnpm build
pnpm lint
pnpm test
pnpm -C apps/api test:e2e
pnpm mobile:analyze
pnpm mobile:test
```

## 6. Current alpha limits

- Crypto is still mock-only.
- The transfer UX is alpha scaffolding, not a full multi-device QR production flow.
- The attachment flow uses placeholder opaque blobs.
- Push fallback is metadata-only and the real APNs/FCM provider is not wired yet.
- Local cache is encrypted at rest for this alpha path, but it is not a production-hardened mobile storage story yet.
