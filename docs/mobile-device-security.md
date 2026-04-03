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
- the local barrier is re-armed
- the privacy shield remains long enough to reduce resume-time content flashes

This protects preview surfaces without claiming universal screenshot blocking across all platforms. iOS public APIs still do not offer full screenshot blocking.

Biometric platform notes:

- Android declares biometric usage explicitly and keeps backup disabled at the app manifest level
- iOS declares Face ID usage text and keeps local unlock device-bound
- local unlock is blocked when rooted or jailbroken heuristics trigger

## Device lifecycle actions

### Log out

Logging out clears:

- session token
- device secret refs
- cache key
- encrypted cache contents

It preserves:

- onboarding acknowledgement
- local app-lock PIN

This is a local session clear only. It does not create recovery.

### Revoke this device

Revoking the current device:

- destroys the active device binding on the server
- clears local session state
- clears local secret material
- clears encrypted cache
- clears the local PIN

It does not create a restore path.

### Wipe local device state

Explicit local wipe removes:

- session state
- local secret material
- encrypted cache
- local PIN
- onboarding acknowledgement

This is intended for destructive local cleanup. It does not move secrets to the server and it does not make recovery possible.

Destructive local actions now require explicit typed confirmation in the UI:

- `WIPE` for local wipe
- `REVOKE` for device revocation

This keeps the no-recovery consequence explicit at the moment of destruction.

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
