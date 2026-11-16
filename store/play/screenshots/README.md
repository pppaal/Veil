# Play Store screenshots

Six phone screenshots, 1080 x 1920, in the order of the App Store shot list
([`../../appstore/screenshot-spec.md`](../../appstore/screenshot-spec.md),
section 4). Upload them in file-name order.

| File | Screen |
|---|---|
| `01-choose-handle.png` | Choose a handle, with a handle typed in |
| `02-chats.png` | Chats: a group and five one-to-one chats |
| `03-chat.png` | A chat with Sam Rivera: a reaction, read receipts, a disappearing message, Sam typing |
| `04-move-to-a-new-phone.png` | Move to a new phone, on the old phone, with its transfer code |
| `05-app-lock.png` | The lock screen with a PIN typed in |
| `06-settings.png` | Settings, from Appearance to the footer of the Security group |

The feature graphic is [`../feature-graphic.png`](../feature-graphic.png),
1024 x 500: the app icon and the word Veil on white, and no other text.

## How they are made

A Flutter test draws all seven files from the app's own screens. From the
repository root:

```bash
cd apps/mobile
flutter test tool/play_store_art_test.dart
```

It writes over the files here and deletes any PNG in this folder it no
longer draws, so a change to one of these screens shows up as a changed
PNG in the diff. Run it again whenever one of them changes, and look at
every PNG before you commit. To look first without replacing anything, add
`--dart-define=PLAY_ART_DIR=/tmp/play-art`. The normal mobile suite
(`test/store/play_listing_art_test.dart`) fails when a file here is not a
size Play takes.

What the test does:

- It opens each screen the way the layout gate does: the real route table
  over the fake server and the seeded account in
  `apps/mobile/test/layout/support`. The names and messages are the gate's
  (Alex Kim, Sam Rivera, Priya Nair, Jonas Weber, Mia Chen and the others).
- The theme is light. The phone is 411 x 731 dp at density 2.625 (420 dpi,
  a Pixel's), which is exactly 1080 x 1920 pixels. The 24 dp status bar is
  left empty.
- Text is Roboto, as on Android. The emoji in the chat is Noto Color Emoji,
  Android's emoji font, read from the `fonts-noto-color-emoji` package or
  the Flutter SDK's engine sources; pass
  `--dart-define=EMOJI_FONT=<path to NotoColorEmoji.ttf>` if neither is
  there.
- The Chats shot leaves out three of the seeded chats: two whose last
  messages are a voice note and a photo, which the app cannot send, and one
  with no messages yet.
- The PNGs are 8-bit RGB without alpha, as Play asks.

Nothing is drawn around a screen: no caption, frame, gradient or device.

The iPhone screenshots are not made this way. iOS draws SF Pro, which the
test cannot render, so they are captured on the iOS Simulator (see the App
Store spec, section 6).
