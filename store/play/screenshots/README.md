# Play Store screenshots

No screenshots are checked in. The earlier set (Korean captions on violet
promo frames) and the feature graphic were removed when the app became
English only and was restyled; nothing from them belongs in the listing.

Make the new set from the restyled app once the screens are final:

- Play needs 2 to 8 phone screenshots (portrait 1080 x 1920 works) and a
  1024 x 500 feature graphic.
- Capture the real screens, in the order of
  [`../../store/appstore/screenshot-spec.md`](../../store/appstore/screenshot-spec.md)
  section 4, with the same names and messages as the App Store set. The
  layout gate renders (`flutter test test/layout --dart-define=SHOTS_DIR=...`,
  see `apps/mobile/README.md`) show every screen at phone sizes and are a
  good check before capturing on a device.
- No caption frames, gradients or device mock-ups. If a caption is needed,
  one plain sentence above the screen is enough.
