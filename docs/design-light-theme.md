# VEIL — Light-first redesign (Veil Violet + Pretendard)

Outcome of the design benchmark: light is the primary surface, the brand
colour moves off generic iOS blue onto **Veil Violet**, and KO+EN type is
unified with **Pretendard**.

## What changed in code

- `lib/src/app/veil_app.dart` — `themeMode: ThemeMode.light` (light is now
  the default surface; switch to `ThemeMode.system` to auto-follow the OS).
- `lib/src/core/theme/veil_theme.dart`
  - Brand primary → **Veil Violet**: `#6E56F8` (light) / `#8B7BFF` (dark).
  - `primaryGradient` → `#7B66FF → #6E56F8` (message bubbles, CTAs).
  - `fontFamily: 'Pretendard'` on the base theme (falls back to the system
    font until the font files are bundled — see below).

The light and dark `VeilPalette`s already existed; only the brand tones and
default mode changed. Dark remains available and on-brand for the security
identity.

## Why Veil Violet

Signal, Telegram, and Messenger all lead with blue, so VEIL's old iOS-blue
primary blended into the field. Violet ties to the product name ("veil"),
differentiates instantly, and is a natural evolution of the existing purple
accent.

## Pretendard install — done

The font is bundled and active. The four static weights (Regular 400,
Medium 500, SemiBold 600, Bold 700, ~1.5 MB each / ~6 MB total) live in
`apps/mobile/assets/fonts/` and are declared under `flutter: fonts:` in
`apps/mobile/pubspec.yaml`, so `fontFamily: 'Pretendard'` now renders the
real typeface on both platforms.

The SIL Open Font License ships alongside the binaries at
`apps/mobile/assets/fonts/OFL.txt` (required by the license).

To update Pretendard later, replace the `.otf` files from
https://github.com/orioncactus/pretendard/releases and bump the note here.

## Verification status

These changes were authored without a Flutter SDK in the work environment,
so they are **not compile-verified here**. They are mechanical (colour
literals + one enum + a fontFamily string) and should be confirmed with a
local `flutter run` / `flutter analyze`. Note the mobile build also has a
**pre-existing, unrelated** analyzer break (Flutter SDK drift in
`pageTransitionsTheme` / providers) that predates this change — see the
mobile CI notes.
