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

## Finishing the Pretendard install

The font *family name* is already wired in the theme; it renders with the
platform default until the actual files ship in the bundle. The binary
font files are **not** committed (keep the repo lean / they are SIL OFL but
large), so add them once:

1. Download Pretendard (SIL OFL, free for commercial use):
   https://github.com/orioncactus/pretendard/releases
2. Copy these weights into `apps/mobile/assets/fonts/`:
   `Pretendard-Regular.otf`, `Pretendard-Medium.otf`,
   `Pretendard-SemiBold.otf`, `Pretendard-Bold.otf`.
3. Add to `apps/mobile/pubspec.yaml` under `flutter:`:

   ```yaml
   fonts:
     - family: Pretendard
       fonts:
         - asset: assets/fonts/Pretendard-Regular.otf
           weight: 400
         - asset: assets/fonts/Pretendard-Medium.otf
           weight: 500
         - asset: assets/fonts/Pretendard-SemiBold.otf
           weight: 600
         - asset: assets/fonts/Pretendard-Bold.otf
           weight: 700
   ```
4. `flutter pub get` and rebuild.

> Do not declare the `fonts:` block before the files exist — Flutter fails
> the build on a missing font asset. That is why this PR wires only the
> `fontFamily` string and leaves the asset declaration for the step above.

## Verification status

These changes were authored without a Flutter SDK in the work environment,
so they are **not compile-verified here**. They are mechanical (colour
literals + one enum + a fontFamily string) and should be confirmed with a
local `flutter run` / `flutter analyze`. Note the mobile build also has a
**pre-existing, unrelated** analyzer break (Flutter SDK drift in
`pageTransitionsTheme` / providers) that predates this change — see the
mobile CI notes.
