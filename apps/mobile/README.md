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
do not wait; such a text's timer also starts when it is sent. The cross on a photo or file that is uploading or failed cancels
it and removes the message.

A received photo of up to 10 MB is fetched when its message arrives, while
the app is open and unlocked, unless the chat waits on a safety number change
or an account hold or is a 1:1 with a blocked account; files and larger
photos download on a tap. A download is refused above 50 MiB or for an id
that is not a UUID, cut off at the size the pointer allows, and checked
against its digest before anything is decrypted. A photo shows only when its
bytes are JPEG, PNG or WebP within the decode limits, and opens full screen
with a tap, where Save keeps a copy on the phone. A file opens with a tap: in
another app on Android, in Quick Look on iOS, and in the in-app viewer when it
is a JPEG, PNG or WebP. The long-press menu can save either. On iOS a photo or
video that the in-app viewer cannot show goes to Save, never to Quick Look.
File, Save and opening a file exist only on Android and iOS, where
`flutter_file_dialog` and the `veil/file_open` channel run: the Windows
desktop build offers Photos only under the plus, shows no Save, and opens a
received file only when it is a photo, in the in-app viewer (any other file
says "Can't open in this version").

Downloaded and sent blobs stay sealed, in one flat folder (`veil_media/` in
app support) under random names of 64 hex characters. Which blob belongs to
which message is kept only in the `media_blobs` table of the encrypted
database. The folder is capped at 1 GiB, least recently used first, never
touching a blob that is still uploading, and a blob goes when its message
expires, or when its chat leaves the list. Decrypted bytes live only in
memory and are dropped on lock. Decrypted files are made only to open a file
or to save a photo or a file: a copy in `veil_open/` under the app's cache
folder (`getTemporaryDirectory()`: `cacheDir` on Android, `Library/Caches` on
iOS), and on iOS, while the save screen is up, the save screen's own copy
under the file's name in the system temporary folder (`tmp/`), deleted when
it returns. The `veil_open/` copies go when Quick Look closes or the save screen
returns (a Save copy also on lock), when their message expires, after 10
minutes (a sweep runs every 60 seconds) and at start. On the sending side, a
picked photo or file is a plaintext copy in the staging folder
(`veil_attachment_cache` in the same cache folder) until it is sealed, the
pick is cancelled, or 10 minutes after a lock held it for its chat; the
picker's own copy is moved there at once. On iOS the system temporary folder
the plugins write to is emptied after each pick and each save. Staging, the
pickers' own copies and (iOS) the system temporary folder are emptied at
every start, before the lock screen is passed, so nothing a crash left
survives a restart.

A file opens through the app's own channel, `veil/file_open`
(`lib/src/core/platform/file_open_channel.dart`, `FileOpenChannel.kt`, the
`FileOpenPlugin` in `AppDelegate.swift`): on Android a viewer in its own task,
reading through the app's FileProvider, which serves `veil_open/` and nothing
else; on iOS Quick Look, presented over the app.

A picker, the save screen and, on iOS, Quick Look run inside
`SystemSheetGrace` (`lib/src/app/system_sheet_grace.dart`). On iOS they are
part of the app, so only a real move to the background locks it, or, once a
sheet has been up for 3 minutes, any step away from the app, and the lock
closes them. On Android they are other apps' screens, and going Home
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
lines, the app's own notices and expired messages. Muted chats, message
requests and 1:1s with a blocked account count too, in grey.

The mark moves to the newest message whenever a chat is on screen: when it
opens, when the app comes back to it from the background, the lock screen, a
sheet or a page, and with each batch of messages that arrives while it is
open. Each move clears the chat's notification and sends at most one read
receipt, for the newest message from someone else that opened (none with read
receipts off). A chat that waits on a safety number change or an account
hold, a 1:1 whose account has a safety number change waiting in another
chat, and a 1:1 with a blocked account send no receipt at all: the mark
still moves, and what was read then is never receipted later. A message
request sends none either until it is accepted; Accept then sends one, for
the newest message read (next section).

An unread row in Chats has its name in bold and a count, or a dot when the
chat was only marked unread. A long press offers Mark as read or Mark as
unread, and muting. The Chats tab shows how many chats are unread, leaving
out muted chats, message requests and blocked 1:1s. A chat opens with an
"unread messages" line above the first new one, and a button takes the list
back to the newest message.

A new database holds a marker row (`~baseline`). The first chat list after
it marks every listed chat read, so an account that was just created or
moved to this phone starts without badges for messages it already had.
`clearAll` (sign-out and wipe) and the upgrade to schema 12 write the marker
again.

## Message requests and scam warnings

All of this is worked out on the phone, and nothing about it is sent: not
the text, not a warning or its reason, not the words that matched, not who
an account is to this phone, not whether a chat is a request, not a link.
Block, Report and Leave use the routes and fields they always use. The
checks are fixed rules in `lib/src/core/safety/`, which may import only
`dart:core`, `dart:collection`, `dart:math` and its own files
(`scripts/crypto-architecture-check.mjs`). What the phone records lives in
one keystore document, `contact_trust.v1`, in the conversation policy
scope, which sign-out erases. The privacy policy needed no change.

**Who an account is.** The phone puts each account in the first of these
that holds:

1. changed: a safety number change about it is waiting, a 1:1 with it is
   held, or a new device of its was admitted in the last 7 days;
2. verified: every key this phone pinned for it is verified;
3. saved: a nickname names it, and has for at least 7 days (or since before
   this version);
4. known: a 1:1 with it was accepted at least 7 days before and holds a text
   or file this phone sent, or, when this version first ran, held a message
   the server labels as the user's own; in a group, also a group this phone
   created or accepted at least 7 days before;
5. new.

**Message requests.** A chat is a request until it is accepted, and an
accepted chat stays accepted. It is accepted by Accept; by starting it from
a typed handle (New chat, or Message on a contact); by creating the group;
by a text or file this phone sends in it (never a system line, a reaction
or a timer change, nor a message the server labels as the user's own); by
verifying the other side; for a 1:1, by a nickname saved for its handle
before the chat first appeared; and for a group, when every other member is
verified, saved or known. The first chat list after install, upgrade or a
move accepts every chat in it. Until a chat is accepted:

- the request bar takes the text field's place: Block, Report and Accept in
  a 1:1, Leave and Accept in a group. Accept is a plain button, not a filled
  one, while a look-alike or family-claim banner shows;
- no read receipt, typing indicator or reaction goes out, and a photo or
  file is fetched only when tapped. With read receipts on, Accept sends one
  receipt, for the newest message read;
- a screenshot sends no notice (the phone still buzzes), a long press
  offers no reactions, and the chat menu has no Disappearing messages;
- the Chats row says "Message request" instead of the text, its badge is
  grey, and the Chats tab count leaves it out. A Chats search hit in it
  quotes no text either: it says "Message request". A notification for it
  says "Message request" too, where the app raises one (the Android beta has
  no push notifications);
- every link asks first.

The delivered tick is not withheld: the server marks a message delivered
when this phone fetches it, so the sender sees that it reached the phone.

Until the document is read and the first chat list has been taken in, no
chat shows as a request, but every chat holds back receipts, typing and
automatic fetches. If the document cannot be read, the phone tries again
with the next change after 1, 5 and 30 seconds; if the last try fails too,
requests, risk lines, the family-claim banner and the verify nudge are off
until the next sign-in, while look-alike checks against verified contacts
and the link sheets still work. A document that is there but cannot be
parsed counts as missing, so the first list accepts every chat again.

**Risk lines.** Each text from someone else is read with up to four
earlier texts from the same sender in the last 24 hours. A line under the
bubble names one reason, in one of three tones: muted, warn or danger. A
family or new-phone claim counts only from a new account the user did not
start the chat with, or a changed one. A money ask from a known, saved or
verified sender needs urgency, secrecy, someone else's account or an excuse
not to call to count, and an ID ask urgency, secrecy or an excuse not to
call. A verified sender gets at most the muted line. A file named `.apk`,
`.xapk` or `.apks` gets the app-file line from any sender. There is no line
on your own messages, the app's notices, or a message that did not open.
The rules read Korean and English text; the app's screens stay English.

**Banners.** In a 1:1, or a group with one other member, at most one trust
banner shows, after the safety number notices:

- look-alike: the other account's handle imitates a verified contact's or
  one saved for a week: a swapped or look-alike character, a suffix such as
  `_new` or `2`, the same nickname, or a handle like `mom_new` when a
  contact is saved as Mum. It has no action and cannot be dismissed.
- family claim: a new account the user did not start the chat with (or a
  changed one) has a family-word handle, or one of its last 50 texts says it
  is family or on a new phone. It says to call the number you already have,
  with Verify (the safety number page) when no other notice is up.
- verify nudge: in a 1:1 with a saved contact who is not verified, once the
  loaded history holds at least 20 messages, 5 of them yours, "Check
  {name}'s safety number" with Verify, on at most three chat openings.

Saving a nickname or waiting ends neither warning; verifying the account
does. A group with more members gets no trust banner.

**Links and app files.** Links in a text are underlined and can be tapped
(while a search runs, its hits win and links are plain). A tap opens a link
at once only in an accepted chat, on your own message or one from a
verified contact, and only when the link looks ordinary. Anything else asks
first with a sheet that shows the domain and the whole address: the plain
sheet (Open, Copy link), or the strong one (Don't open, then Open anyway in
red, and Copy link) for a link to an app file, a short link or hidden host,
or a domain that only looks like a known site's. A host with a %-escape, a
character outside ASCII (a full stop other than "." included) or an `xn--`
label gets the strong sheet from anyone, and every sheet names the domain a
browser would open (escapes decoded, other full stops read as dots,
full-width letters and digits read as plain ones, any label still outside
ASCII in its `xn--` form). naver.me, kko.to and me2.do get the plain sheet,
unless the link is an app download, hidden or a look-alike, which
`linkRiskOf` checks first. Open hands that exact address to another app
through `url_launcher` 6.3.2, for http and https only. It adds no
permission: its Android plugin brings one activity, `WebViewActivity`,
which is not exported and which the app does not use, and the app's
manifest gains a `<queries>` entry for https links. Opening a link leaves
Veil, so with App lock on, coming back locks it. The phone never fetches,
previews or expands a link. Opening or saving a received app file asks
first through the strong sheet.

**Known limits.**

- A long con passes the week rule: after weeks of small talk the account is
  known, and a money ask from it is flagged only with urgency, secrecy,
  someone else's account or an excuse not to call.
- A handle the user typed (New chat) or saved (Contacts) because a scammer
  gave it outside Veil makes the chat one the user started: it is no request
  and gets no family-claim line or banner. Money, code, link and app-file
  warnings still apply.
- The first run after install, upgrade or a move to a new phone accepts
  every chat the server lists then: the phone trusts that listing once.
- Rules can be dodged: text in a photo, new spellings, a whole message in
  English with a space between every letter. No warning does not mean a
  message is safe.
- A few real company domains (for example epost.kr) can get the strong link
  sheet.
- A screenshot notice or a timer change made in a stranger's chat in the
  seconds before the first chat list loads can still go out. A reaction is
  refused then too.
- The delivered tick still shows for a request.
- A group with more than one other member gets no look-alike or
  family-claim check.
- The Android beta has no push notifications, so the "Message request"
  notification text applies only where the app raises notifications.

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
- photo and file opening: prefetch, download tickets, size caps, digest check, the viewer, open a file (another app on Android, Quick Look on iOS), save
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
