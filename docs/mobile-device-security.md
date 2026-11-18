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

- message contents, keys and the fields that name or describe a message (peer handles, display names, message-type metadata, attachment pointers) are encrypted before persistence
- ids, conversation orders, timestamps and delivery states are plain columns, as are the read marks and the media index below: the database file's own encryption is all that protects them
- unencrypted legacy payloads are rejected
- cache schema upgrade clears legacy rows that predate the stricter metadata encryption
- SQLite opens from app-support storage, not user-facing documents storage
- SQLite is built with `sqlite3mc` hooks and opens with a device-local database key derived from secure storage
- legacy plaintext cache files are migrated in place to an encrypted database on first open
- SQLite startup enables `secure_delete`, `foreign_keys`, `trusted_schema = OFF`, `temp_store = MEMORY`, and WAL mode
- cache directories are marked out of iCloud backup on iOS
- wiping local device state rotates away the cache key and clears cached rows

This is still a private-beta posture, not an audited secure database design.

### Read marks

Unread counts come from one read mark per chat in the `conversation_read_marks`
table: the conversation order of the newest message read on this phone and
whether the chat was marked unread. The count itself is never stored, and the
server learns nothing from it. A read receipt goes out only when receipts are
on, and never from a chat that waits on a safety number change or an account
hold, from a 1:1 whose account has a safety number change waiting in another
chat, or from a 1:1 with a blocked account. A new database holds one reserved
row, `~baseline` (no relay id can take that form), which the first chat list
after it spends: every listed chat is marked read through its last message,
so a phone that was just set up or moved to shows no badges for what its
chats held before. Sign-out and wipe (`clearAll`) and the upgrade to schema
12 write that row again.

## Photos and files

### Sealed media folder

Downloaded and sent attachments are kept sealed, exactly as they were
uploaded or downloaded and checked against their digest, in one flat folder
(`veil_media/` under the app support folder). Each blob has a random name of
64 hex characters that says nothing about its message. Which blob belongs to
which message (conversation id, attachment id, digest, size, expiry, last use)
is kept only in the `media_blobs` table inside the encrypted database, and the
blob's key stays in the encrypted content store. Recency is that table's
column: the app never reads or sets the files' own times. So someone who can
read the app's sandbox still sees how many blobs there are, their padded
sizes and the file system's times on each file, which show roughly when each
was written: when you sent it, when a photo of up to 10 MB arrived (or first
came on screen, if it arrived while the app was closed or locked), or when you
first opened a file or another photo with a tap.

The folder is capped at 1 GiB, least recently used first, and never loses a
blob whose upload is still pending. A blob goes when its message expires, when
its chat leaves the list, and on sign-out and wipe; at start, files without a
row and rows without a file are deleted. The folder is excluded from backup.

### Decrypted bytes

A photo is decrypted in memory when it is shown, into a cache of at most 48 MB
keyed by conversation id, attachment id and digest (so a reused attachment id
never returns another message's bytes), and Flutter's image cache. Both are
emptied when the app locks, on sign-out and on wipe, and an entry goes when
its blob does. Showing a photo writes nothing decrypted to disk; opening a
file and saving a photo or a file do (below).

### Plaintext copies to open a file or save a photo or a file

Opening a file (in another app, in Quick Look or in the in-app viewer), and
saving a photo or a file, needs a plaintext file. It is written to
`veil_open/<random>/<name>` under the app's temporary folder, and deleted:

- on iOS, when Quick Look closes, whether the user or the lock closed it;
- for a Save copy, when the save screen returns, and on lock;
- when its message expires;
- by a sweep every 60 seconds while the app runs, and on resume, for any copy
  older than 10 minutes;
- at every start, and on sign-out and wipe.

An Android copy opened in another app is not deleted on lock, since that app
may still be reading it. The app a file is opened with, and wherever the user
saves it, may keep its own copy, which Veil cannot reach; the Save dialog says
so ("Other apps, and any cloud you save it to, can open it.").

### Picker and save copies

The pickers and the save screen write copies of their own. On Android,
`image_picker` writes to `cacheDir/<uuid>/` and `flutter_file_dialog` to
`cacheDir/file_dialog-<uuid>/`; Veil moves each picked copy into its staging
folder or deletes it at once, and deletes Android's lost picks (a pick whose
activity died) at start. On iOS both plugins write to the system temporary
folder (`tmp/`, `NSTemporaryDirectory()`): `image_picker_*` files, the picked
file under its original name, the copy handed to the save screen and the
document picker's `-Inbox/` folder. Veil empties that folder at start, after
each pick has been copied into staging, after each save returns, and on
sign-out and wipe. A picked file stays in staging only until it is sealed or
the pick is cancelled, and staging is emptied at every start, so no plaintext
pick survives a crash under its real name.

### Opening a file in another app

There is no third-party file opener. The app's own channel, `veil/file_open`,
opens a file. On Android it starts the viewer with `ACTION_VIEW` in a new task
(`FLAG_ACTIVITY_NEW_TASK`, `FLAG_ACTIVITY_MULTIPLE_TASK`, a read grant only),
through the app's own FileProvider, which serves `veil_open/` and nothing else.
On iOS it presents Quick Look over the app. On iOS a photo or video that the
in-app viewer cannot show goes to the Save flow instead of Quick Look.

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
- the app lock is re-armed. Only on Android does a system screen the user
  opened from Veil hold it off: while a photo picker, the file picker or the
  save screen is up, Veil is not locked, and the return locks only if that
  screen opened more than 3 minutes before. On iOS those screens and Quick
  Look are inside the app, so opening one is not leaving it, and leaving with
  one up locks at once (below)
- the privacy shield remains long enough to reduce resume-time content flashes

This protects preview surfaces without claiming universal screenshot blocking across all platforms. iOS public APIs still do not offer full screenshot blocking.

Biometric platform notes:

- Android declares biometric usage explicitly and keeps backup disabled at the app manifest level
- iOS declares Face ID usage text and keeps local unlock device-bound
- local unlock is blocked when rooted or jailbroken heuristics trigger

### The lock and system screens

A photo picker, the file picker, the save screen and, on iOS, Quick Look are
screens the user opens from Veil and expects to come back from. They run inside
`SystemSheetGrace` (`apps/mobile/lib/src/app/system_sheet_grace.dart`):

- On iOS they are presented inside the app, so the lifecycle changes they
  cause are not the user leaving. The lock follows only a real move to the
  background (the scene's own background event, as Home without a sheet), and
  that also closes them. A sheet that has been up for 3 minutes no longer
  holds the lock off.
- On Android a picker or the save screen is another app's screen, so Veil is
  hidden while it is up and is not locked for it. The next return to Veil
  locks if the screen opened more than 3 minutes before. So going Home from a
  picker leaves Veil unlocked for up to 3 minutes. Time is counted on the wall
  clock and on a monotonic clock, whichever says more, and a wall clock set
  back counts as past the limit. One gap remains: the monotonic clock stops
  while the phone sleeps, so a phone that sleeps while away and has its date
  set back to just after the picker opened comes back unlocked.
- Opening a file in another app on Android gets no grace: Veil locks as soon
  as it is hidden, and the file opens in that app's own task, so returning to
  Veil from the launcher or the app switcher shows the lock screen, never the
  file.

Every lock ends a running picker or save screen as cancelled; a result that
still arrives afterwards is held for the chat it was picked in (a pick) or
deleted (anything else). On iOS the lock also closes Quick Look and every
presented sheet, without animation, and the native privacy cover stays up
until the lock screen has been drawn (or the app is unlocked, or 1.5 seconds
after it became active), so the document never shows between the two.

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
- iOS cache, media and attachment directories are marked as excluded from backup where the platform allows per-path control

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
