# VEIL Internal Alpha Desktop QA

Use this when the Windows desktop client is already running.

## Preconditions

- `pnpm docker:alpha:up`
- `pnpm alpha:smoke`
- `pnpm dev:mobile:desktop`

## Fast Path

1. On the splash screen, confirm bootstrap finishes without hanging.
2. On the warning screen, confirm the copy explicitly says there is no backup and no recovery.
3. Enter a display name, then create a new account.
4. Choose a handle and watch the bind phases complete:
   - generating local identity
   - registering handle
   - requesting challenge
   - verifying device
5. Confirm the app lands on the conversation list.
6. Confirm the empty state is visible and the primary action is `Start direct chat`.
7. Create a direct chat with another registered handle.
8. Open the chat room and send one normal text message.
9. Enable disappearing mode and send one more message.
10. Confirm the bubble shows a remaining lifetime label.
11. Open the attachment screen, send the placeholder attachment, and confirm an encrypted attachment card appears.
12. Resolve the attachment download ticket and confirm the dialog returns a signed opaque URL.
13. Open Settings -> App lock, set a PIN, lock the app, and unlock with the PIN.
14. Open Settings -> Device transfer and confirm the old-device requirement is explicit.
15. Open Security Status and confirm it shows:
    - bound device state
    - local secret refs
    - app lock status
    - realtime state
    - local cache state
    - mock crypto warning

## Failure Checks

1. Try an invalid or duplicate handle and confirm the error is readable.
2. Try an unknown handle in `Start direct chat` and confirm the error is readable.
3. Enter a wrong PIN and confirm the unlock failure copy is clear.
4. Confirm Settings copy never implies backup, restore, or recovery.

## Exit Criteria

- No crash on onboarding, bind, chat, attachment, lock, transfer, or settings.
- No raw exception strings in banners.
- No route hangs.
- No copy that weakens the no-recovery model.
