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

## Switched-off features

This is a text-only build: it sends and receives text messages, reactions
and the notices around them, and has no screen for anything it cannot do
end to end (no calls, media picker, voice messages, sticker picker, stories
or assistant, and no screen that sends an attachment). The one constant left
is `kAttachmentsEnabled` (`lib/src/features/attachments/attachments_feature.dart`),
false because the app has no file picker. While it is false the composer has
no attach button, and an attachment a web client sent is shown as what it is
(its kind and size) with a line saying this version cannot open it; the
transfer code underneath (sealing, upload tickets, retry) is real and stays
tested, since it is what a file picker will feed. The route table
(`lib/src/app/router/app_router.dart`) has no route for anything the build
cannot do, and a location no route has (an old link, a mistyped one) opens
the conversation list instead of the router's "Page Not Found". The bottom
bar is Chats, Contacts, Settings.

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
first, with the bar carrying the safety number, the search and the
disappearing timer. From 1120 px the same list and the same chat sit side by
side, each under its own bar (`ChatPaneBar` in `chat_bar.dart`): the list in
a 380 px pane with the open conversation's row marked, the chat in the rest,
its messages and composer at most 760 px wide. Neither pane puts anything
above its rows or messages but a notice that asks for a decision. Every
screen opens with its control or its list under a 52 px bar, never with a
slogan, a paragraph or a row of chips (`docs/mobile-design-system.md`,
sections 1 and 11). `test/phone` holds the behaviour of both layouts
(search, timer, safety number, back, the panes).

A row of the list quotes its conversation's last message when that is a
text this device decrypted, read from the device's own content store; every
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
- upload-ticket/complete attachment send scaffold
- download-ticket resolution scaffold for encrypted attachments
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
