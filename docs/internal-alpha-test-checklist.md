# VEIL Internal Alpha Test Checklist

## Onboarding And Binding
- Launch the app and confirm the splash screen routes correctly after bootstrap.
- Read the onboarding warning and confirm the copy clearly states: no backup, no recovery, no restore path.
- Create an account with and without a display name.
- Register a handle and confirm the UI shows the local bind flow stages: generate identity, register, challenge, verify.
- Confirm registration failures render readable error banners instead of raw exceptions.

## Conversation Flow
- Open the conversation list with an empty account and confirm the empty state is clear and actionable.
- Start a direct chat by handle and confirm the list refreshes after channel creation.
- Open a chat room and confirm loading, empty, and populated states are visually distinct.
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

## Attachment Flow
- Open the attachment screen and confirm the flow copy matches the encrypted-envelope architecture.
- Send an attachment placeholder and confirm it queues locally, uploads, then resolves into an encrypted attachment card.
- Resolve a download ticket from the attachment card and confirm the dialog returns the opaque ticket URL.

## Lock And Session
- Open App Lock with no PIN set and confirm the screen explains there is no remote reset path.
- Set a PIN, confirm the second-entry check, and confirm the app unlocks locally.
- Re-open the lock screen and confirm PIN unlock works.
- If biometrics are available, verify biometric unlock works and failure states are readable.
- Background the app and confirm the preview is obscured and the session returns behind the local barrier.
- Use `Wipe local device state` and confirm session, PIN, and onboarding state are removed locally.

## Transfer And Settings
- Open Device Transfer on the old device and confirm the flow makes the old-device requirement explicit.
- Run init and approve on the old device and confirm a copyable transfer payload is produced.
- On a fresh device, open `Transfer from old device`, import the payload, and complete transfer.
- Let a transfer or claim expire and confirm the UI blocks completion and clearly requires a fresh session.
- Confirm the new device becomes authenticated and the old device is logged out after completion.
- Open Settings and confirm revoke and logout copy do not imply recovery.
- Revoke the current device and confirm the session is cleared locally.

## Security Status
- Open Security Status and confirm it accurately reflects device binding, local secret refs, app lock, runtime connectivity, and cache state.
- Confirm the screen still warns that mock crypto is active in internal alpha.

## Private Beta Release Gate
- Run `pnpm ci:api` and confirm build, lint, policy checks, unit tests, and API e2e all pass.
- Run `pnpm ci:mobile` and confirm codegen, analyze, and mobile tests all pass.
- Run `pnpm alpha:smoke` against a running stack and confirm the smoke script succeeds end to end.
- Confirm no crash-reporting SDK has been added and no mobile console logging is present.
- Confirm release notes and tester instructions still state that mock crypto is active and production security claims are not yet valid.
