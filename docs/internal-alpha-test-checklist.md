# VEIL Internal Alpha Test Checklist

## Onboarding And Binding
- Launch the app and confirm the splash screen routes correctly after bootstrap.
- Read the onboarding warning and confirm the copy clearly states: no backup, no recovery, no restore path.
- Create an account with and without a display name.
- Register a handle and confirm the UI shows the local bind flow stages: generate identity, register, challenge, verify.
- Confirm registration failures render readable error banners instead of raw exceptions.

## Conversation Flow
- Open the conversation list with an empty account and confirm the empty state is clear and actionable.
- Start a direct chat by handle and confirm the list refreshes after conversation creation.
- Use local conversation search and confirm matches are filtered by handle or display name without any server-side search dependency.
- Open a chat room and confirm loading, empty, and populated states are visually distinct.
- Use local message search inside a populated chat room and confirm results come only from the device-local cached archive.
- Send a text message with disappearing mode off and confirm it first appears as `Queued` and then settles to `Sent`.
- Send the same message again only by forcing a retry path and confirm it does not duplicate after the relay ack returns.
- Send a text message with disappearing mode on and confirm the chat bubble shows the remaining lifetime.
- Wait for a disappearing message to expire and confirm it disappears from the local UI.
- Kill and relaunch the app after queueing a message offline and confirm the queued state restores from local cache.
- Reconnect the relay after queueing a message offline and confirm the outbox drains automatically without manual refresh.
- Disconnect and reconnect realtime while a second device sends messages, then confirm the active chat resyncs the missing envelopes.
- Keep the recipient offline with no active socket, send a message, then confirm only metadata wake-up behavior is assumed and the full envelope arrives after reconnect/sync.
- In a long thread, use `Load older` repeatedly and confirm older pages append without reordering or duplicating messages.
- Confirm sender-side delivery labels move through `Queued`, `Sent`, `Delivered`, and `Read` with no backwards regressions.
- On wide desktop or tablet layouts, confirm the conversation list stays visible beside the active chat.

## Attachment Flow
- Tap + in a chat, choose Photos, pick a photo and send it; confirm the photo shows in the bubble at once, with a ring while it uploads, and on the other phone after its download.
- Choose File, pick a PDF, confirm the dialog names the file and the chat, and send it; on the other phone, confirm a tap downloads it and opens it in another app.
- Pick a JPEG or an MP4 as a file and confirm the dialog adds "A photo or video sent as a file keeps any location saved in it."
- Cancel an upload with the cross and confirm the message is removed and nothing is sent.
- Let an upload fail (go offline), confirm "Not sent. Tap to retry." under the bubble, then retry and confirm it sends.
- Open a received photo full screen, tap Save, and confirm the dialog "Save to your phone?" appears before the system save screen.

## Lock And Session
- Open App Lock with no PIN set and confirm the screen explains there is no remote reset path.
- Set a PIN, confirm the second-entry check, and confirm the app unlocks locally.
- Re-open the lock screen and confirm PIN unlock works.
- If biometrics are available, verify biometric unlock works and failure states are readable.
- Background the app and confirm the preview is obscured and the session returns behind the app lock.
- Use Settings > `Sign out`, type the handle, and confirm the session, keys and PIN are removed (the onboarding acknowledgement stays). With the network off, confirm nothing is erased and the app says it couldn't sign out: there is no offline wipe.

## Transfer And Settings
- Open Device Transfer on the old device and confirm the flow makes the old-device requirement explicit.
- Issue a transfer code on the old device and confirm it can be copied; approve the claim there once the new device shows one.
- On a fresh device, open `Transfer from old device`, paste the code, register the device, and complete the trusted-device join.
- Let a transfer or claim expire and confirm the UI no longer offers completion and clearly requires a fresh session: step 1 is marked `Expired` on both devices, the old device issues a new code there and the new device pastes it there. The expired code is refused if it is pasted again.
- Confirm the new device becomes authenticated and the old device is logged out after completion.
- Confirm Settings lists no devices: an account is active on one device at a time, and `Move to a new phone` sits in the Account group.
- With `Move to a new phone` open, lock the app and unlock it: confirm the screen is back, with Settings under it.
- Open Settings and confirm the Sign out and Delete account dialogs do not imply recovery, and that each asks for the user's own handle typed first. Signing out erases this device's keys: confirm the copy says so.

## Settings > Security
- Confirm the Security group shows App lock, Lock now, Screenshots, App switcher preview and Notifications with their values, and one footer line: "The encryption hasn't been independently audited yet." (in a development-crypto build: "This build uses test encryption. Don't use it for real chats."). A `VEIL_ENV=production` server refuses to boot until that audit is attested.

## Private Beta Release Gate
- Run `pnpm ci:api` and confirm build, lint, policy checks, unit tests, and API e2e all pass.
- Run `pnpm ci:mobile` and confirm codegen, analyze, and mobile tests all pass.
- Run `pnpm alpha:smoke` against a running stack and confirm the smoke script succeeds end to end.
- Confirm no crash-reporting SDK has been added and no mobile console logging is present.
- Confirm release notes and tester instructions state that the production crypto adapter is wired but external audit attestation is still pending, and that production boot remains blocked by `VEIL_AUDITED_CRYPTO_ATTESTED`.
