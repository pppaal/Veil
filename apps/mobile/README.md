# Veil mobile

The Flutter app for iOS and Android. It is English only (`lib/src/l10n/app_en.arb`
is the one string file), and its look follows
[`docs/mobile-design-system.md`](../../docs/mobile-design-system.md).

To run it:

1. Run `flutter pub get`
2. Run `dart run build_runner build --delete-conflicting-outputs`
3. Start the API locally from the repo root with `pnpm dev:api`
4. Run Flutter with API defines, for example:

```bash
flutter run \
  --dart-define=VEIL_API_BASE_URL=http://10.0.2.2:3000/v1 \
  --dart-define=VEIL_REALTIME_URL=http://10.0.2.2:3000
```

## What the app leaves out

The app has no screen for anything it cannot do end to end: no calls, voice
messages (one a web client sent shows as what it is, with a line saying this
version can't open it), sticker picker, stories or assistant. The route table
(`lib/src/app/router/app_router.dart`) has no route for anything the build
cannot do, and a location no route has (an old link, a mistyped one) opens
the conversation list instead of the router's "Page Not Found". The bottom
bar is Chats, Contacts, Settings.

## Photos and files

The plus at the start of a chat's composer opens a sheet with two rows,
Photos and File. It is there whenever the chat can be written to and has no
safety number change or account hold waiting. Photos opens the system photo
picker (`image_picker`: the Android Photo Picker, PHPicker on iOS) and File
the system document picker (`flutter_file_dialog`). Neither asks for a
permission. The Android manifest declares no camera, microphone,
`READ_MEDIA_*` or storage permission, and iOS has one usage string for it,
`NSPhotoLibraryUsageDescription`, which `image_picker` requires and the
system picker never shows. One photo per pick, with no caption.

A picked photo is decoded by the engine at a long edge of at most 1600 px
(never larger than it was) and encoded again on the phone: JPEG at quality
80, or PNG when it has transparency. Only its pixels go out, so its location,
camera details and every other kind of metadata stay behind. A JPEG may be up
to 200 megapixels and any other format up to 40, since the engine decodes
those at full size first; a larger photo, or one the phone cannot decode, is
not attached. The photo shows full screen with Send before it goes. A file
goes as it is, up to 25 MB, the web's limit. Its confirm dialog names the
file and the chat, and for a photo or video picked as a file adds "A photo or
video sent as a file keeps any location saved in it." Its name is cleaned as
the web cleans it and travels only inside the encrypted message.

Send seals the photo or file at once, in an isolate, with the web's scheme
(`encryptAttachmentV2`) and deletes the plaintext copy; only the sealed blob
is uploaded. The message itself is encrypted once, after the upload, and a
disappearing timer is stamped then, as the web stamps it. A chat sends in
order, so a text sent after a file waits for its upload, while other chats
do not wait. The cross on a photo or file that is uploading or failed cancels
it and removes the message.

A received photo of up to 10 MB is fetched when its message arrives, while
the app is open and unlocked, unless the chat waits on a safety number change
or an account hold or is a 1:1 with a blocked account; files and larger
photos download on a tap. A download is refused above 50 MiB or for an id
that is not a UUID, cut off at the size the pointer allows, and checked
against its digest before anything is decrypted. A photo shows only when its
bytes are JPEG, PNG or WebP within the decode limits, and opens full screen
with a tap, where Save keeps a copy on the phone. A file opens in another app
with a tap, and the long-press menu can save either. On iOS a photo or video
that the in-app viewer cannot show goes to Save, never to Quick Look.

Downloaded and sent blobs stay sealed, in one flat folder (`veil_media/` in
app support) under random names of 64 hex characters. Which blob belongs to
which message is kept only in the `media_blobs` table of the encrypted
database. The folder is capped at 1 GiB, least recently used first, never
touching a blob that is still uploading, and a blob goes when its message
expires. Decrypted bytes live only in memory and are dropped on lock. The
only plaintext files are the copies made to open or save a file, in
`veil_open/` under the temporary folder. They go when Quick Look closes or
the save screen returns (a Save copy also on lock), when their message
expires, after 10 minutes (a sweep runs every 60 seconds) and at start. A picker's copy is moved into the
staging folder at once and stays there only until it is sealed or the pick
is cancelled; nothing in staging survives a restart. On iOS the system
temporary folder the plugins write to is emptied after each pick and each
save.

A file opens through the app's own channel, `veil/file_open`
(`lib/src/core/platform/file_open_channel.dart`, `FileOpenChannel.kt`, the
`FileOpenPlugin` in `AppDelegate.swift`): on Android a viewer in its own task,
reading through the app's FileProvider, which serves `veil_open/` and nothing
else; on iOS Quick Look, presented over the app.

A picker, the save screen and, on iOS, Quick Look run inside
`SystemSheetGrace` (`lib/src/app/system_sheet_grace.dart`). On iOS they are
part of the app, so only a real move to the background locks it, and the
lock closes them. On Android they are other apps' screens, and going Home
from one leaves Veil unlocked for up to 3 minutes. Opening a file in another
app on Android gets no grace: Veil locks as soon as it is hidden.
[`docs/mobile-device-security.md`](../../docs/mobile-device-security.md) has
the details, and [`docs/attachment-flow.md`](../../docs/attachment-flow.md)
the whole path.

No plugin or native channel runs under `flutter test`. Each sits behind a
provider (`attachmentPickerProvider`, `imagePreparerProvider`,
`attachmentOpenerProvider`, `systemSheetGraceProvider`,
`attachmentStoragePathsProvider`), with fakes in `test/support`
(`FakeAttachmentPicker`, `FakeAttachmentOpener`, `RecordingPlatformSecurity`).
Tests root the storage folders, the system temporary folder included, in
temp folders and use a `MemoryMediaIndex`, so purges and sweeps really run.
The fake relay issues upload and download tickets by the API's rules and has
knobs for failures, tampering, oversize and holding a transfer.

## Unread counts

Each chat has one read mark on the phone, in the `conversation_read_marks`
table of the encrypted database: the order of the newest message read here,
and whether the chat was marked unread. The count is worked out from the
mark and the messages, never stored, and the server learns nothing new. It
counts other people's messages above the mark, leaving out reactions, system
lines, the app's own notices and expired messages. Muted chats and 1:1s with
a blocked account count too, in grey.

The mark moves to the newest message whenever a chat is on screen: when it
opens, when the app comes back to it from the background, the lock screen, a
sheet or a page, and with each batch of messages that arrives while it is
open. Each move clears the chat's notification and sends at most one read
receipt, for the newest message from someone else that opened (none with read
receipts off). A chat that waits on a safety number change or an account
hold, or a 1:1 with a blocked account, sends no receipt at all: the mark
still moves, and what was read then is never receipted later.

An unread row in Chats has its name in bold and a count, or a dot when the
chat was only marked unread. A long press offers Mark as read or Mark as
unread, and muting. The Chats tab shows how many chats are unread, leaving
out muted chats and blocked 1:1s. A chat opens with an "unread messages" line
above the first new one, and a button takes the list back to the newest
message.

A new database holds a marker row (`~baseline`). The first chat list after
it marks every listed chat read, so an account that was just created or
moved to this phone starts without badges for messages it already had.
`clearAll` (sign-out and wipe) and the upgrade to schema 12 write the marker
again.

## Layout gate

`flutter test test/layout` opens every screen at three phone sizes
(360x640, 390x844, 412x915) in English, the app's only language, and
scrolls it to its end. The app bundles no UI font, so the gate loads Roboto
from `test/fonts` (wider than SF, so it measures the worst case). Besides
each screen's everyday state it opens the states that take room away (the keyboard, stacked warnings, a search, larger
system text), the sheets and menus that only appear on a tap, and the states
a chat can be in (a group, reactions, the peer typing, a message from a
legacy frame, search results). A case fails

- on any layout error the framework reports (an overflowing row or column,
  unbounded constraints),
- when the messages of a chat, the rows of the conversation list or the
  rows of the contacts get less than 45% of the screen height (96 px under
  the keyboard or warnings),
- when a control is smaller than 44x44, on every screen (no screen is
  exempt: `tapTargetExemptScreens` in `screen_cases.dart` is empty). A
  control at an edge of the screen is measured like any other; only a
  modal's scrim is left out,
- when a chat does not show the action of each of its warnings whole, where
  a tap reaches it. A button cut off by the area it scrolls in is no layout
  error, so the gate looks for it,
- when the control a screen is for is not on the first screenful. A case
  names it (`primaryAction`: the first input, the primary button, the first
  setting of the settings screen); with the keyboard closed it must be
  wholly on screen at 390x844 and 412x915, and begin on screen at 360x640.

Each case is rendered once more in the light theme (390x844, every
screenful), held to layout errors and tap targets. Nothing in the gate reads
colours: a light render that passes can still hold text nobody can read, so
look at its PNGs (`<case>__390x844__en__light.png`). The palette itself is
held to WCAG AA in both themes by `test/theme/veil_palette_contrast_test.dart`. The wide cases open the
two-pane shell with a chat at 1280x800 and 1440x1000, and the chat on an
upright tablet (1024x1366, which is under the 1120 px the two panes need),
with and without warnings, held to what a phone's chat is held to: layout
errors, the messages' share, each warning's action whole on screen, and tap
targets.

It runs with the rest of `flutter test`.

To look at the screens, pass a directory: the run then also writes one PNG
per case and a `report.json`.

```bash
flutter test test/layout --dart-define=SHOTS_DIR=/tmp/veil-shots
flutter test test/layout --dart-define=SHOTS_DIR=/tmp/veil-shots --dart-define=SHOTS_PAGES=all
```

`SHOTS_PAGES=all` adds a PNG for every further screenful of a scrolling
screen. A new screen needs a case in `test/layout/support/screen_cases.dart`,
and a new sheet or state of an existing screen deserves one.

Nothing is listed as failing today. `test/layout/known_phone_layout_failures.dart`
is the list of what is known to fail, one line per case with the sizes it
fails at and the defects it shows. It is empty, and a test of the gate keeps
it empty, so a screen that stops fitting is fixed, not listed. The gate
fails for a listed case that passes, or fails another way, as it does for an
unlisted one that fails.

`flutter test tool/play_store_art_test.dart` draws the Google Play
screenshots and feature graphic into `store/play` from the screens the gate
opens (`store/play/screenshots/README.md` says what it draws). It sits under
`tool/`, so `flutter test` does not run it; `test/store/play_listing_art_test.dart`,
which it does run, holds the committed files to the sizes Play takes.

## UI strings gate

`node scripts/mobile-ui-strings-check.mjs` (from the repository root; part
of `pnpm ci:mobile` and the mobile CI job) reads the Dart files that build UI
text (every `features/*/presentation` folder, `shared/presentation`, `app/`
and `core/errors/user_facing_error.dart`) and fails on a user-facing string
literal that is not an `AppLocalizations` lookup. It catches what no render
opens: a toast, a dialog, an error. Route paths, keys, map keys, compared
values, patterns, URLs, exception and log messages and identifier-shaped
tokens are not UI text, unless they stand where text goes: the argument of
`Text`, a `label`, a `title`, a `tooltip` (`Text('send')` is a finding).
There is no comment that silences a finding. Two lists at the top of the
script, by file and literal:

- `KNOWN_HARDCODED`: the copy that is still hard-coded today. It only
  shrinks: an unlisted literal fails, and so does a listed one the file no
  longer holds. What is left is the thirteen English sentences of
  `core/errors/user_facing_error.dart`: controllers and logs have no locale,
  so `formatUserFacingError` keeps them, and a screen shows such an error
  through `veilErrorText` (`shared/presentation/veil_error_text.dart`), which
  finds the sentence's code and reads its text from the ARB file
  (`test/phone/error_language_phone_test.dart`). A failure without a code is
  shown as it came: a relay's own words, and the English of a failure the
  data layer words itself and the formatter does not know. The script does
  not read the data layer, so those sentences are on no list.
- `NOT_COPY`: what the gate takes for text and is not copy (an example
  handle in a hint, a file name), each with its reason. This is the way out
  for a false positive: add the literal with why it is not copy, rather than
  rewriting code to get past the gate.

`--list` prints every literal it finds, as the lists spell it.

## Phone and wide layouts

Under 1120 px the conversation list is the whole screen and a chat opens on
top of it (`conversation_list_phone.dart`, `chat_phone_layout.dart`): content
first, with the bar carrying the safety number, the search and a menu (the
disappearing timer, muting, and in a 1:1 reporting and blocking the peer).
From 1120 px the same list and the same chat sit side by
side, each under its own bar (`ChatPaneBar` in `chat_bar.dart`): the list in
a 380 px pane with the open conversation's row marked, the chat in the rest,
its messages and composer at most 760 px wide. Neither pane puts anything
above its rows or messages but a notice that asks for a decision. Every
screen opens with its control or its list under a 52 px bar, never with a
slogan, a paragraph or a row of chips (`docs/mobile-design-system.md`,
sections 1 and 11). `test/phone` holds the behaviour of both layouts
(search, timer, safety number, back, the panes).

A row of the list quotes its conversation's last message when that is a
text this device decrypted, read from the device's own content store; a
photo is a small glyph and "Photo", a file a glyph and its name, and every
other kind is named by what it is. After the list is fetched, the messenger
loads the history of each conversation it names and never loaded
(`DecryptedMessageCache.loadUnheld`), so a message that arrived while the
app was closed is quoted without its chat being opened. Nothing is marked
read for a preview, an expired message is not quoted, and the list is not
built behind the app lock.

The screens around the account (privacy notice, Before you start, Create
account, Choose a handle, App lock, Move to a new phone, Safety number,
Security) open with the field or button they are for. Each security fact is
said in one place only (`docs/mobile-design-system.md`, section 9): the
loss of a phone, for one, is said on Before you start, in the Security
footer and in the confirm dialogs that destroy something. The privacy notice
and Before you start keep their button in a bar under the text that
scrolls. Move to a new phone is three numbered steps per phone, of which
only the step in hand shows its controls; a code to carry to the other phone
is shown with a copy button, and what approving or finishing leads to is
said above the button that does it. What an action came to is one line
under the button of the step that was acted on, and scrolls itself into
view. A session or claim that ran out puts the first
step back in hand on its side: the claim's window is the session's, so the
new device can neither register again nor finish on the code it holds, and
the step that says so is the one that takes the new code
(`test/phone/device_transfer_expired_claim_phone_test.dart`). A safety
number comes before how to compare it and the button that records the
comparison; a change to review comes before everything else. Security lists
one row per fact, in groups, with its state as a word at the row's end.
`test/phone/identity_screens_phone_test.dart` holds that behaviour.

A chat's warnings are notices while they fit above the messages, which keep
96 px. When they do not (a small phone with the keyboard up), each warning
is one row with its title and its action, and only more rows than fit
scroll. `VeilFirstThatFits` makes that choice during layout. Opening a
message that a search found moves the list to it however far back it is
(`navigation_target_jump.dart`).

## Release builds

A release build must name its server and pin its TLS keys. With the
development defaults (a localhost endpoint, or no `VEIL_TLS_PINS`) a release
build stops at the configuration-error screen and the security status screen
reports it as blocked (`VeilConfig.validateRuntimeConfiguration`). `VEIL_ENV`
is an API server variable; the app ignores it.

```bash
flutter build appbundle --release \
  --dart-define=VEIL_API_BASE_URL=https://api.example.org/v1 \
  --dart-define=VEIL_REALTIME_URL=https://api.example.org \
  --dart-define=VEIL_TLS_PINS=spki:<current>,spki:<next> \
  --dart-define=VEIL_OBJECT_STORAGE_HOSTS=<bucket host> \
  --dart-define=VEIL_OBJECT_STORAGE_PINS=spki:<bucket pin>
```

The realtime client appends `/v1/realtime` itself. Pin format and rotation
are described at the top of `lib/src/core/network/pinned_http_client.dart`;
ship the next pin before rotating.

## libsignal bridge (opt-in, never built yet)

Default Android and iOS builds leave the native libsignal bridge and Signal's
native libraries out; the Dart libsignal adapter then reports the bridge as
unavailable. To build it in:

- Android: `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal --android-project-arg=veil.libsignal=true`
  (compiles `android/app/src/libsignal` and adds `org.signal:libsignal-android`).
- iOS: add `Runner/Crypto/VeilCryptoBridge.swift` and the LibSignalClient
  package to the Runner target, register `VeilCryptoBridgePlugin` in
  `AppDelegate.swift` (see the comment there), and build Dart with
  `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`.

The Kotlin bridge type-checks against libsignal-client 0.86.5; neither bridge
has been built into an app on a real toolchain or run.

Current mobile wiring includes:

- register -> challenge -> verify -> session persistence
- direct conversation create/list and encrypted envelope send/list
- photo and file sending: system pickers, re-encoding, sealing, upload tickets, retry
- photo and file opening: prefetch, download tickets, size caps, digest check, the viewer, open with another app, save
- websocket conversation sync
- local PIN/biometric app lock hooks
- device transfer init/approve/complete scaffold
- Drift-backed cache service scaffold pending codegen

Crypto status: the runtime adapter (`createConfiguredCryptoAdapter` in
`lib/src/core/crypto/crypto_adapter_registry.dart`) wires the real
`LibCryptoAdapter` (X25519 ECDH + HKDF-SHA256 + AES-256-GCM). The
`MockCryptoAdapter` is retained for unit tests only and is never used at
runtime. Production builds are still gated behind the
`VEIL_AUDITED_CRYPTO_ATTESTED` define until an external crypto audit
clears the engine.
