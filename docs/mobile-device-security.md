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

- Android encrypted shared preferences
- iOS/macOS keychain entries marked `first_unlock_this_device`
- no synchronizable keychain setting

This means VEIL does not rely on cloud-synced secret storage for the active device.

## Local cache at rest

The local conversation cache is protected with an app-layer encrypted-at-rest wrapper.

- cache rows store encrypted values only
- unencrypted legacy payloads are rejected
- wiping local device state rotates away the cache key and clears cached rows

This is still a private-beta posture, not an audited secure database design.

## App lock and privacy posture

App lock is local only.

- PINs are stored as derived verifiers, not raw values
- PIN format is numeric only, 6 to 12 digits
- biometrics are used only through the device-local unlock path
- there is no remote unlock, PIN reset, or recovery override

When VEIL leaves the foreground:

- the UI is obscured for app-switcher privacy
- the local barrier is re-armed

This protects preview surfaces without claiming universal screenshot blocking across all platforms.

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
