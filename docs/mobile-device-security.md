# VEIL Mobile Device Security

## Scope

This document covers the local-device protections in the current VEIL private beta. It does not claim audited production cryptography. It documents the current guardrails and the boundaries that still require external review.

## Product posture

- No backup
- No recovery
- No password reset
- Device-bound identity
- Old-device-required transfer
- No server-side unlock or restore

If the active device is lost, VEIL cannot restore the account or message history.

## Local sensitive material

Sensitive device material is stored locally only:

- device identity private reference
- device auth private key
- session access token
- encrypted local-cache key
- app-lock PIN verifier

The mobile client stores these items with `flutter_secure_storage` using:

- Android encrypted shared preferences with reset-on-error handling
- iOS/macOS keychain entries marked `unlocked_this_device`
- no synchronizable keychain setting
- app-specific secure-storage account naming

This means VEIL does not rely on cloud-synced secret storage for the active device.

Additional hardening in the current branch:

- PIN verifiers use PBKDF2-HMAC-SHA256 with a stronger versioned verifier format
- PIN comparisons use constant-time verification
- repeated failed PIN attempts trigger a temporary local lockout
- wiping local device state also clears local PIN throttle state

## Local cache at rest

The local conversation cache is protected with an app-layer encrypted-at-rest wrapper and an encrypted SQLite container.

- cache rows store encrypted values only
- peer handles, display names, and message-type metadata are encrypted before persistence
- unencrypted legacy payloads are rejected
- cache schema upgrade clears legacy rows that predate the stricter metadata encryption
- SQLite opens from app-support storage, not user-facing documents storage
- SQLite is built with `sqlite3mc` hooks and opens with a device-local database key derived from secure storage
- legacy plaintext cache files are migrated in place to an encrypted database on first open
- SQLite startup enables `secure_delete`, `foreign_keys`, `trusted_schema = OFF`, `temp_store = MEMORY`, and WAL mode
- cache directories are marked out of iCloud backup on iOS
- wiping local device state rotates away the cache key and clears cached rows

This is still a private-beta posture, not an audited secure database design.

## App lock and privacy posture

App lock is local only.

- PINs are stored as derived verifiers, not raw values
- PIN format is numeric only, 6 to 12 digits
- repeated failed PIN attempts cause a temporary local-only lockout
- biometrics are used only through the device-local unlock path
- there is no remote unlock, PIN reset, or recovery override

When VEIL leaves the foreground:

- Android sets a secure window flag to block screenshots and recent-app thumbnails
- iOS installs a native privacy shield over the scene before app-switcher snapshots
- the Flutter UI is also obscured for app-switcher privacy
- the app lock is re-armed
- the privacy shield remains long enough to reduce resume-time content flashes

This protects preview surfaces without claiming universal screenshot blocking across all platforms. iOS public APIs still do not offer full screenshot blocking.

Biometric platform notes:

- Android declares biometric usage explicitly and keeps backup disabled at the app manifest level
- iOS declares Face ID usage text and keeps local unlock device-bound
- local unlock is blocked when rooted or jailbroken heuristics trigger

## Device lifecycle actions

Settings has two account actions, both in its last group (Account), and both
ask the user to type their own handle ("Type @alex to confirm.") before
anything happens (`settings_danger_zone.dart`). There is no device list: an
account is active on one device at a time (devices are created only at
sign-up and when a transfer completes, which revokes the old device in the
same transaction), so there is no other device to remove.

### Sign out

Sign out runs `AppSessionController.revokeCurrentDevice`:

- it signs a step-up proof with this device's auth key and asks the server to
  revoke this device (`POST /devices/revoke`; the server requires the proof
  for the calling device and for the last active one);
- only once the server has revoked it does the phone erase its state
  (`_clearLocalState(preservePin: false)`): session tokens, device secret
  refs, pending transfer, cache key and encrypted cache, PIN and PIN
  throttle, ratchet sessions, group sender keys, prekeys, safety-number
  verifications and every scoped store. The onboarding acknowledgement
  stays;
- if the server cannot be reached or refuses, nothing is erased and the
  screen says "Couldn't sign out. Check your connection and try again." The
  one exception is a server that answers `device_not_active`: the device was
  already revoked, so the phone erases itself as it does everywhere else.

So a phone that cannot reach the server cannot be signed out or erased from
the app. This is deliberate: erasing a device the server still counts as
active would leave the account with an active device that nobody holds. The
app has no offline wipe.

With no recovery and one device per account, signing out loses the account
for good, and the dialog says so.

### Delete account

Delete account runs `AppSessionController.deleteAccount`: a step-up proof,
then the server deletes the account (`DELETE /account`), and only then does
the phone erase its state as above, the onboarding acknowledgement
included. A refused or unanswered request erases nothing.

### Moving to a new phone

Approving a transfer on the old phone (behind a confirm dialog that shows the
new phone's key fingerprint) lets the new phone complete it; the server
revokes the old device in the same transaction. The old phone erases itself
the next time the server answers it with `device_not_active`.

### Not reachable from the UI

`AppSessionController.logout` (a best-effort server logout that keeps the
PIN) and `wipeLocalDeviceState` (a local-only erase) remain in the code, but
no screen calls either of them.

## Backup posture

Native platform backup paths are intentionally constrained:

- Android manifest backup is disabled with `allowBackup="false"`
- Android data extraction rules exclude cloud backup and device-to-device transfer
- iOS cache and attachment directories are marked as excluded from backup where the platform allows per-path control

VEIL does not add any recovery export or shadow-copy path on top of these controls.

## Device transfer rules

Transfer is a live handoff, not a backup flow.

- the old device must start the transfer
- the new device must register its own claim
- the old device must approve that exact claim
- the new device must complete before the transfer window expires
- when the new device becomes active, the old device is revoked

Expired sessions and expired claims must be restarted. VEIL does not extend them through a recovery path.

## Review notes

Before external security review:

- replace the mock `CryptoEngine` adapter with an audited implementation
- review local cache key lifecycle on iOS and Android hardware
- review background privacy behavior on supported platforms
- review all revoke and transfer edge cases on real devices

## Rooted / jailbroken device strategy

Native heuristics are now wired into the mobile runners and fed back into the Flutter security UI.

Current checks include:

- Android test-keys builds
- Android `su` / Magisk artifact detection
- Android executable `su` availability
- iOS jailbreak artifact detection
- iOS `cydia://` URL handler checks
- iOS sandbox escape probe
- iOS suspicious dynamic-library checks

Current behavior:

- VEIL surfaces the integrity state in the security panel
- VEIL blocks local unlock on compromised devices
- VEIL does not fall back to a server-side recovery or escrow model

Remaining review risk:

- heuristic detection can still produce false negatives and should not be treated as hardware attestation
- Android native enforcement could not be built on this workstation because no Android SDK is installed here
- iOS screenshot blocking remains platform-limited by public APIs
