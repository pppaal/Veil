# Veil design system

Applies to apps/mobile and apps/web-demo. It replaced the earlier violet, Pretendard, Korean-and-English design (and docs/design-light-theme.md) in full. Decisions recorded here were taken on 2026-11-15 and are not re-opened by implementers: English only; one blue brand colour; platform font; black or white pages; no decoration layer.

Code comments cite this document by section number (veil_theme.dart, veil_ui.dart, tool/brand.dart, the contrast test), so keep the numbering. Line numbers in sections 6.1, 7.10 and 11 point at the code as it was before the redesign (commit e006063); they say what was removed, not where to look today. Where the code deliberately departs from a number below, section 16 says so; it outranks the section it amends.

## 0. The direction in one paragraph

Veil behaves like the Messages or Settings app that came with the phone. Pages are white or black. Lists are full-bleed rows with 0.5dp inset separators. Type is the platform's own font in sentence case. One blue appears in exactly five places (primary button fill, own bubbles, the switch track, the active tab, text links) and nowhere else. Nothing floats unless it is a sheet, dialog or menu. Nothing is explained twice: a security fact lives in one place (section 9). The rebuild is mostly deletion: 18 of 28 shared widgets, about 130 ARB keys, every gradient, glow, blur, pill row, hero card, eyebrow label and metric tile. A design-literate person must be unable to tell which team made it; it must look like every careful team's work: boring in the right places, precise where state matters (ticks, timers, verified, stale), identical in temperament in light and dark.

## 1. Rules that outrank everything below

1. One brand colour per mode. `primary` (fill) is used only for: FilledButton fill, own bubble fill, Switch track on, the send circle, the unread badge, the launcher tile. `primaryStrong` (brand text) is used only for: active tab icon and label, TextButton and link text, the focused floating label, progress indicators, the label of a selected segment, filter chip or own reaction on `primarySoft`. Not for icons in rows, section headers, avatars, app bars, the verified mark (that is `success`), or borders.
2. No gradients, no glows, no blur, no shadows on a page. The only shadow in the product is `VeilElevation.modal` on dialogs, sheets and menus, light mode only.
3. Hierarchy is surface tier plus hairlines: canvas < surface < surfaceAlt/surfaceRaised, 0.5dp `stroke` lines. Never blur, never a coloured border, never a radius larger than 18 except the pill shapes listed in section 4.
4. Sentence case everywhere. No `.toUpperCase()`, no positive letterSpacing, no tracked small-caps labels, no Title Case titles, no "VEIL" (the product is "Veil"; `appTitle` = `Veil`).
5. One fact, one place. Section 9 is the only permitted location of each security fact. A fact shown anywhere else is a defect.
6. A notice (`VeilNotice`) appears only when the user has a decision or an action to take. Information is plain text (`bodySmall textMuted`) or a group footer, never a tinted box.
7. Light and dark are both first-class: every token has a value in both, every screen is rendered in both by the layout gate, and the contrast unit test (section 14) holds both to WCAG AA.
8. Screens open with their control or their list under a 52dp bar, never with a slogan, a paragraph or a row of chips.

## 2. Colour tokens

Field names of `VeilPalette` (apps/mobile/lib/src/core/theme/veil_theme.dart) are kept so call sites compile: `canvas, canvasAlt, surface, surfaceAlt, surfaceRaised, stroke, strokeStrong, primary, primaryStrong, primarySoft, text, textMuted, textSubtle, success, warning, danger`, plus `outgoingMeta` (the outgoing bubble meta colour below, a named token so it is one value in one place). `VeilPalette.light`, `VeilPalette.dark`, `VeilPalette.forBrightness(brightness)`. Delete `accent`, `accentSoft`, `primaryGradient`, `surfaceGradient`, `surfaceOverlay`. All ratios are WCAG 2.x, computed and asserted by apps/mobile/test/theme/veil_palette_contrast_test.dart. When the contrast test was written first against these values, every pair passed: no hex value below was changed for contrast.

### 2.1 Light (`VeilPalette.light`)

| Token | Hex | Use | Verified |
|---|---|---|---|
| canvas | #FFFFFF | page of Chats, Contacts, chat room, auth, onboarding, lock | |
| canvasAlt | #F2F2F7 | page of grouped screens: Settings, Profile, Blocked accounts, App lock settings, One-time link, Device transfer | |
| surface | #FFFFFF | group container on a grouped page, list rows, bars | |
| surfaceAlt | #E9E9EB | incoming bubble, search and composer field fill, disabled button fill, notice fill on white pages | |
| surfaceRaised | #FFFFFF | sheets, dialogs, menus (the only shadowed surfaces) | |
| stroke | #C6C6C8 | 0.5dp separators, bar hairline, field border at rest | 1.71 vs white (non-text, decorative) |
| strokeStrong | #AEAEB2 | focused field border 1dp, sheet drag handle | |
| text | #000000 | all body and title text | 21.0 / 18.8 / 17.3 on canvas / canvasAlt / surfaceAlt |
| textMuted | #5F5F64 | subtitles, meta, headers, footers, notice body, placeholder | 6.35 / 5.69 / 5.24 |
| textSubtle | #8E8E93 | disabled text, chevrons, disabled glyphs only; never body, never placeholder | 3.26 on white (UI component threshold 3:1); never placed on canvasAlt or surfaceAlt directly |
| primary | #1F5FD6 | brand fill (rule 1) | white on it 5.73 |
| primaryStrong | #1F5FD6 | brand text (rule 1) | 5.73 / 5.13 / 4.72 on canvas / canvasAlt / surfaceAlt |
| primarySoft | #1F1F5FD6 (12%) | selected segment, filter chip, own reaction fill | primaryStrong on the composite over canvas or surface 4.82; over surfaceAlt only 4.00, so never put a selected chip or segment on a surfaceAlt fill |
| danger | #B8000E | destructive row title, destructive TextButton, "Not sent", danger notice icon | 6.90 / 6.18 / 5.69 |
| warning | #9A4600 | warn notice icon, stale status text, timer glyph in bar | 6.46 / 5.79 / 5.33 |
| success | #15683A | verified mark, "Verified" / "Available" status text | 6.83 / 6.12 / 5.64 |
| outgoing bubble | #1F5FD6 fill, #FFFFFF text, #DCE7FB meta | | text 5.73, meta 4.60 |
| incoming bubble | #E9E9EB fill, #000000 text, #5F5F64 meta | | 17.3, 5.24 |

### 2.2 Dark (`VeilPalette.dark`)

| Token | Hex | Use | Verified |
|---|---|---|---|
| canvas | #000000 | every page, including grouped pages (dark grouped = black page with lifted groups) | |
| canvasAlt | #000000 | same as canvas; the token stays so `grouped` compiles | |
| surface | #1C1C1E | group container, bar on grouped pages, list rows on grouped pages | |
| surfaceAlt | #26262B | incoming bubble, field fill, notice fill, disabled fill | text 13.5 |
| surfaceRaised | #2C2C2E | sheets, dialogs, menus (no shadow; 0.5dp strokeStrong top edge on sheets) | |
| stroke | #2C2C2E | separators on black, bar hairline | |
| strokeStrong | #3A3A3C | separators inside #1C1C1E groups, focused field border | |
| text | #F2F2F7 | | 18.8 / 15.3 / 13.5 on canvas / surface / surfaceAlt |
| textMuted | #9A9AA1 | | 7.51 / 6.09 / 5.39; 4.98 on surfaceRaised |
| textSubtle | #8E8E93 | disabled, chevrons | 6.44 / 5.22 |
| primary | #2A63CC | brand fill | white on it 5.59 |
| primaryStrong | #6FA3FF | brand text | 8.36 / 6.77 / 5.99 |
| primarySoft | #296FA3FF (16%) | selected fills | primaryStrong on the composite 6.93 over canvas, 5.13 over surface, 4.52 over surfaceAlt |
| danger | #FF6B5E | text and icon only, never a fill | 7.52 / 6.09 / 5.39 |
| warning | #FF9F0A | | 10.2 / 8.28 / 7.33 |
| success | #30D158 | | 10.4 / 8.42 / 7.45 |
| outgoing bubble | #2A63CC fill, #FFFFFF text, #E3ECFB meta | | 5.59, 4.70 |
| incoming bubble | #26262B fill, #F2F2F7 text, #9A9AA1 meta | | 13.5, 5.39 |

### 2.3 Colour rules

- `ColorScheme.onPrimary` = `Colors.white` in both modes (today dark uses black-on-violet; that goes).
- The launcher tile is the one place `primary` is used as a background outside the five uses in rule 1 (resolves the earlier contradiction).
- Filled red exists nowhere. Destructive confirmation buttons are `TextButton` in `danger`; destructive rows are `danger` titles with no chevron.
- Tone colours are never fills. The old `_paletteFor` tints (border 0x66, fill 0x1F) are deleted; a notice's fill is `surfaceAlt`, its tone is the icon colour only.
- Web demo CSS tokens carry the same hex values (section 12.1).

## 3. Type

Decision: platform default font. `ThemeData.fontFamily` is null; iOS renders SF Pro, Android renders Roboto, and the OS text-size setting applies. Pretendard (bundled for Korean parity, which no longer exists) is removed from pubspec.yaml and assets/fonts. Every TextStyle below sets an explicit `height`, so line boxes are font-independent.

Test harness consequence: `VeilTheme.light({String? fontFamily})` / `VeilTheme.dark({String? fontFamily})`, production passes nothing. `loadTestFonts()` in the layout probe (test/layout/support/phone_layout_probe.dart; call it from `setUpAll`) loads apps/mobile/test/fonts/Roboto-Regular.ttf, Roboto-Medium.ttf, Roboto-Bold.ttf (Apache-2.0, LICENSE.txt alongside; these are test files, not app assets) under three family names: `VeilTestSans` (`layoutFontFamily`, which the layout world passes to `VeilTheme`), `Roboto` (what the theme resolves on the Android test platform when no family is passed) and `monospace` (Roboto Regular stands in for the safety-number digits; there is no RobotoMono in test/fonts). Then the icon fonts from FontManifest.json; the app bundles no UI font. Roboto is wider than SF, so the gate measures the worst case.

### 3.1 Scale (sp = Flutter logical px, scaled by the OS). Sentence case, letterSpacing 0 unless shown, weights 400/500/600/700 only.

| Style | Size / height / weight / tracking | Only used for |
|---|---|---|
| headlineLarge | 28 / 1.2 / 700 / -0.3 | "Before you start", "Veil is locked" |
| headlineMedium | 22 / 1.25 / 600 / -0.2 | empty-state title on wide layouts, profile name; at 400 in `monospace` with tracking 0, the claim code on the new phone (section 11.13) |
| titleLarge | 17 / 1.3 / 600 / -0.2 | app bar title, dialog title, sheet title, empty-state title |
| titleMedium | 16 / 1.3 / 600 / -0.1 | conversation name, a person's name in a row led by an avatar; w700 variant for an unread conversation name only; w400 variant for every other row title (settings, sheet options, actions, field labels), as Signal, WhatsApp and Telegram set them |
| titleSmall | 15 / 1.3 / 600 / 0 | notice title, step title, sender name in group bubbles (tinted, section 6.3) |
| bodyLarge | 16 / 1.4 / 400 | message text, composer text, input text |
| bodyMedium | 15 / 1.4 / 400 | row subtitle, dialog body, paragraph copy, notice body |
| bodySmall | 13 / 1.35 / 400 | snippet in a conversation row, group header and footer, footnotes, list timestamps, day divider (w500) |
| labelLarge | 15 / 1.2 / 600 / 0 | button labels (Filled, Outlined, Text) |
| labelMedium | 13 / 1.2 / 500 / 0 | status text at a row's trailing edge (Verified, On, Off, Blocked, Hidden), member chip labels in New group |
| labelSmall | 11 / 1.2 / 500 / 0 | tab bar labels, bubble meta (time, the status glyph, the timer glyph; the words are for screen readers), unread badge count (12 / 600) |
| displayLarge, headlineSmall | deleted from use; left at Flutter defaults | |

`VeilTypography` is deleted; bar titles use `titleLarge`.

AppBar: `titleTextStyle` = titleLarge, `toolbarHeight` 52, elevation 0, `centerTitle` = true on iOS and false on Android (`Theme.of(context).platform`), `backgroundColor` = canvas (canvasAlt on grouped pages), `surfaceTintColor` transparent, `scrolledUnderElevation` 0. `VeilShell` draws its own bar to the same rules rather than using `AppBar`.

### 3.2 Case and characters

- Sentence case for every title, button, header, label and row: "Safety number", "Create account", "Mark as verified", "App lock", "New group", "Move to a new phone".
- Proper nouns and "Veil" capitalised normally; acronyms stay (PIN, QR, TLS). "VEIL" never appears in the UI, the ARB, the web demo or the README prose.
- Digits for numbers ("2 messages", "60-digit"). Times in the platform's locale format.
- Allowed non-ASCII: the ellipsis U+2026 for in-progress labels ("Connecting…", "Saving…"); the curly apostrophe is not required, the straight ASCII apostrophe is the house style ("don't"). Banned: em dash U+2014, en dash U+2013 (write "to" or a comma), middle dot U+00B7 outside the conversation row meta, bullets, arrows, emoji in any UI string.

## 4. Radius, spacing, sizes, elevation

`VeilRadius` (names kept): xs 6 (filter chip), sm 8 (segmented control, menu item hover), md 10 (text field, buttons, group container, notice, snackbar), lg 14 (dialog), xl 18 (bubble main corners, composer field), pill 999 (avatar, switch, unread badge, send circle only). Bubble tail corner is a literal 4 (last/single) or 6 (first/middle). `cardTheme` radius md with no side; `ListTileThemeData.shape` = none (radius 0).

`VeilSpace` (names kept): xxs 4, xs 8, sm 12, md 16, lg 20, xl 24, xxl 32; xxxl and hero are deleted with their last reference. Page side gutter 16. VeilShell default `padding` becomes `EdgeInsets.zero` (lists are full-bleed); form screens pass `EdgeInsets.fromLTRB(16, 16, 16, 24)`.

Row heights: 44 min (one line), 52 (title + subtitle), 60 (leading avatar 40), 72 (conversation row, avatar 48), 64 for the dense conversation row at 360 width. Group header: bodySmall textMuted, 16 top / 6 bottom. Group footer: bodySmall textMuted, 6 top / 16 bottom, 16 side inset. Bar 52 + status inset. Tab bar 56 + bottom inset. Buttons 48 (TextButton and IconButton 44x44). Fields 44 (search fields too; the 36dp iOS search field fails the 44 tap-target gate): `InputDecorationTheme.contentPadding` is 12h 11v, which makes a dense field (`isDense: true`) 44.4 tall; with 10v it is 42.4 and fails the gate. A field that is not dense is 48 tall in Flutter whatever the padding, so a field that must be 44 (search) sets `isDense: true`. Bubble padding 12h 8v; gap 2 inside a sender group, 8 between groups, 16 around day dividers. Tap targets: every control 44x44; `SegmentedButton` and `ChoiceChip`/`FilterChip` get `materialTapTargetSize: padded` and sit in a 44-tall row; reaction chips are 28 tall visually with a 44x36 minimum hit box via padding inside the InkWell.

`VeilIconSize` kept: xs 14, sm 18, md 22 (default), lg 28, xl 40.

Elevation: `VeilElevation` keeps only `modal` = `[BoxShadow(color: Color(0x2E000000), blurRadius: 24, offset: Offset(0, 8))]`, the one shadow in the product, light mode only. The themes draw it as Material elevation 8 with `shadowColor` 0x2E000000 on dialogs, menus and modal bottom sheets in light, and elevation 0 in dark; in dark the lift is the surfaceRaised tier plus a 0.5dp strokeStrong line along the top edge of sheets only (a whole outline also drew faint lines down both screen edges). The light `SnackBar` keeps Material elevation 8 too, since white on a white page is otherwise invisible; dark has none. `raised` and `chip` are deleted. No `BoxShadow` anywhere else. Bars are opaque canvas (canvasAlt on grouped pages) with a 0.5dp stroke bottom, painted over the bar's last half point so the bar stays 52 and its content keeps the whole 52; the tab bar's top hairline is painted over the `NavigationBar` the same way. A static hairline is acceptable; scrolled-under appearance is optional.

Motion: `VeilMotion.fast/normal/slow`, `emphasize`, `smooth`, `springGentle` stay; `springResponsive` and `springBouncy` are deleted with `VeilPressable`. No scale-on-press anywhere.

## 5. Icons

Mobile: Material Icons, the outlined family only (`Icons.*_outlined`, or the plain name where no outlined variant exists: `Icons.search`, `Icons.close`, `Icons.arrow_back`, `Icons.done`, `Icons.done_all`, `Icons.chevron_right`). No `_rounded` anywhere (120 refs today). Sizes: 24 in the tab bar and bar actions, 22 default in rows, 20 chevrons and notice icons, 16 verified mark, 14 the bubble ticks and the timer glyph in bubble meta. Bar actions are plain `IconButton`s with no background tile (delete the `IconButtonThemeData.backgroundColor` at veil_theme.dart:534). Tab bar icon pairs: `chat_bubble_outline` / `chat_bubble`, `people_outline` / `people`, `settings_outlined` / `settings`. Back glyph: `Icons.arrow_back_ios_new` 20 on iOS, `Icons.arrow_back` 24 on Android. Verified mark: `Icons.verified` 16 in `success`. Ticks, Signal's check circles: `Icons.schedule` while waiting, one `Icons.check_circle_outline` sent, two overlapping delivered, and for read `MessageReadGlyph` (message_read_glyph.dart), the web's `tick-read` drawn in Flutter: two filled circles, the back one cut to a crescent by a thin ring, each check cut out in the bubble's fill, in the 20 by 14 box delivered takes. Two `Icons.check_circle` stacked fuse into one pill and hide the first check. Never: `radar_outlined`, `priority_high`, `gpp_maybe`, a padlock in the composer, a shield as decoration. Icon colour: `textMuted` by default, `textSubtle` when disabled, the tone colour only inside `VeilNotice` and for status glyphs.

Web demo: one inline SVG sprite (section 12.4), 20px, stroke 1.75, currentColor. No emoji glyph is ever used as an icon or inside a UI string.

## 6. Avatars

### 6.1 Component

`VeilAvatar(name:, seed:, size: 40, group: false, unknown: false)` in shared/presentation/veil_avatar.dart replaces the six draw sites (veil_ui.dart:1080-1148; contacts_screen.dart:169-184, 353-363, 402-414; profile_screen.dart:58-72; the switched-off features' sites are deleted). Flat solid disc, white initial (first grapheme of `name`, upper-cased) at weight 600 and size*0.42, no border, no shadow, no gradient, no presence dot. Sizes: 32 (chat bar, group-bubble sender), 40 (contact rows, sheets), 48 (conversation rows), 56 (safety number and contact sheet header), 72 (profile). `Semantics(excludeSemantics: true)`: the row carries the label.

### 6.2 Colours and hash

Index = FNV-1a 32-bit of the `seed` string (the handle), mod 8. Not `String.hashCode` (unstable across platforms). The same eight colours in both modes; every one verified at 4.5:1 or more for the white initial and at 3:1 or more as a shape against #000000, #1C1C1E, #FFFFFF and #F2F2F7:

| i | Hex | white initial | vs #000 | vs #1C1C1E | vs #FFF | vs #F2F2F7 |
|---|---|---|---|---|---|---|
| 0 | #4F6D8F | 5.36 | 3.92 | 3.17 | 5.36 | 4.81 |
| 1 | #7A5C9A | 5.49 | 3.82 | 3.10 | 5.49 | 4.92 |
| 2 | #A4573F | 5.23 | 4.01 | 3.25 | 5.23 | 4.69 |
| 3 | #3E7D62 | 4.87 | 4.31 | 3.50 | 4.87 | 4.36 |
| 4 | #8A6D2F | 4.87 | 4.31 | 3.49 | 4.87 | 4.37 |
| 5 | #2F7C8A | 4.80 | 4.37 | 3.54 | 4.80 | 4.31 |
| 6 | #9E4F70 | 5.52 | 3.81 | 3.08 | 5.52 | 4.94 |
| 7 | #5E7A3A | 4.86 | 4.32 | 3.50 | 4.86 | 4.36 |

Group conversations: a neutral disc (`VeilAvatar.neutralLight` #6E6E73, white glyph 5.07; `VeilAvatar.neutralDark` #48484A, white glyph 9.12) with `Icons.group_outlined` at size*0.5, never a letter. Unknown or legacy sender (`unknown: true`): the same neutral disc with `Icons.person_outline`. Helpers: `veilFnv1a32(text)`, `veilInitialOf(name)`, `VeilAvatar.indexOf(seed)`, `VeilAvatar.colorOf(seed)`, and the tables `VeilAvatar.colors`, `nameTintsLight`, `nameTintsDark`.

### 6.3 Sender names in group bubbles

The avatar fill colours fail AA as 15sp text (3.96 to 4.55 on #E9E9EB; 3.72 to 4.01 on black), so sender names use a separate tint table indexed by the same FNV index:

| i | Light name tint (on #E9E9EB) | Dark name tint (on #26262B) |
|---|---|---|
| 0 | #3B5673 (6.26) | #8FB0D6 (6.70) |
| 1 | #5B4479 (6.80) | #B9A0DB (6.54) |
| 2 | #7F4030 (6.47) | #E09A85 (6.55) |
| 3 | #2C5D47 (6.27) | #7FC3A6 (7.36) |
| 4 | #674F22 (6.37) | #D1B06B (7.27) |
| 5 | #1F5E69 (6.05) | #7CC2CF (7.51) |
| 6 | #7A3C58 (6.62) | #DB94B3 (6.38) |
| 7 | #45602A (5.85) | #A3C07C (7.45) |

Exposed as `VeilAvatar.nameTint(context, seed)`. The web demo uses the same three tables as `.av-0`…`.av-7` (background) and `.name-0`…`.name-7` (colour) classes (section 12).

## 7. Shared components

Eight widgets remain in apps/mobile/lib/src/shared/presentation/ plus three helpers that are not widgets (`VeilHaptics`, `VeilFirstThatFits`, `showVeilToast`). Everything else is deleted or moved into the one feature that uses it. Enums `VeilTone` (rename of `VeilBannerTone`: info, good, warn, danger) and `VeilButtonTone` (primary, secondary, destructive, ghost) stay; `VeilThemeContext` (`context.veilPalette`, `context.veilPhoneWidth`, which is width < 600) stays. veil_ui.dart exports veil_avatar, veil_bubble, veil_composer, veil_group and veil_notice; `VeilShell` and `VeilBackButton` are imported from veil_shell.dart, `VeilFirstThatFits` from veil_first_fit.dart. The tab shell is `MainTabShell` (app/router/main_tab_shell.dart).

### 7.1 VeilShell (veil_shell.dart)
API kept (`title`, `titleWidget`, `leading`, `actions`, `child`, `maxWidth` 840, `padding`), plus `bool grouped = false` and `String? subtitle`; `VeilShell.barHeight` = 52, `VeilShell.formPadding` = `EdgeInsets.fromLTRB(16, 16, 16, 24)`, `VeilShell.groupedOf(context)` (false inside a popup route). Scaffold + a 52dp opaque bar (a Material in canvas, or canvasAlt when grouped) with a 0.5dp stroke bottom, SafeArea, text-scale clamp 1.3 on the bar, `MediaQuery.withClampedTextScaling` kept. The scaffold paints the page colour (canvasAlt when grouped, canvas otherwise); there is no `ColoredBox` in the body, because a coloured box between a `ListTile` and its Material hides the tile's ink and Flutter reports it as an error, which fails the layout gate. No `extendBodyBehindAppBar`, no gradient, no blobs, no `VeilBlur`. `subtitle` (bodySmall textMuted under the title) is used only by the Chats bar while not connected ("Connecting…", "Offline"). `VeilBackButton` stays here with the platform glyph rule (`Icons.arrow_back_ios_new` 20 on iOS and macOS, `Icons.arrow_back` 24 elsewhere).

### 7.2 VeilGroup and VeilRow (new, veil_group.dart)
Replace `VeilSurfaceCard`, `VeilListTileCard`, `VeilSectionLabel`, `VeilValueRow`, `VeilFieldBlock`.
- `VeilGroup({header, footer, children, inset})`: on a grouped page, a `surface` container, radius 10, 16dp side margins, children separated by 0.5dp lines (`stroke` light, `strokeStrong` dark) inset to the text edge (16, or 56/72 when rows have leading avatars). Header and footer are bodySmall textMuted, sentence case, 16dp inset (header 16 top / 6 bottom, footer 6 top / 16 bottom). On a white page (`grouped: false` in the shell) it draws no container: full-bleed rows with inset hairlines; this is how the Chats and Contacts lists compose. In a sheet, dialog or menu it also draws no container (rows run full-bleed on `surfaceRaised`), and its hairlines there are `strokeStrong` in dark, since `stroke` equals `surfaceRaised` (#2C2C2E). `VeilGroup.isInside(context)` tells a child it sits in a group.
- `VeilRow({title, subtitle, subtitleWidget, leading, trailing, value, status, destructive, onTap, switchValue, onSwitch})`: a `ListTile` with `minTileHeight` 44/52/60, `contentPadding` 16h (the min heights give the vertical room), titleMedium title (600 when a `VeilAvatar` leads the row, a person's name; 400 otherwise), bodyMedium textMuted subtitle (max 2 lines with ellipsis), trailing text `value` in bodyMedium textMuted ("On", "2", "@alex") or `status: (String, VeilTone)` drawn as labelMedium in the tone colour with no fill and no border, `Icons.chevron_right` 20 textSubtle automatically when `onTap != null` and there is no trailing, `Switch` with the brand track. A row is a switch row when `switchValue != null`; without `onSwitch` the switch is disabled (on = `primary` track at 38% alpha with the white thumb; off = `surfaceAlt` track with a `textSubtle` thumb), the title is `textSubtle`, the row does nothing on tap and is announced as disabled (pass `onSwitch: busy ? null : ...` while busy). `destructive: true` draws the title in `danger` with no chevron. The row draws its ink on its own transparent Material. `VeilRow.field(field:, title:, trailing:)` hosts a borderless `TextField` inside a group; standalone fields (auth, search) use the `InputDecorationTheme` directly.

### 7.3 VeilButton (veil_ui.dart)
API kept (`label`, `onPressed`, `tone`, `icon`, `expanded`). The theme does the look: FilledButton 48dp, radius 10, `primary` fill, white label labelLarge, disabled `surfaceAlt` / `textSubtle`; OutlinedButton 48, radius 10, transparent fill, 1dp `stroke`, label in `text`; TextButton 44, `primaryStrong` label; `destructive` = TextButton in `danger`. Icon 18 before the label, 8 gap. Haptics unchanged.

### 7.4 VeilAvatar (veil_avatar.dart): section 6.

### 7.5 VeilNotice (new, veil_notice.dart)
Replaces `VeilInlineBanner` (47 refs), `VeilNoticeRow` (1), `VeilDestructiveNotice` (6) with the same parameters (`title`, `message`, `tone`, `icon`, `dense`, `actionLabel`, `onAction`) plus `margin`. Fill `surfaceAlt`, radius 10, no border, padding 12, margin 12h on white pages (`margin` overrides it); inside a `VeilGroup` it is a row (no margin, no radius). An empty `title` counts as none. `VeilNotice.denseHeight` = 44; `VeilNotice.iconFor(tone)` gives the icons below. Leading icon 20 in the tone colour: info `Icons.info_outlined` textMuted, warn `Icons.warning_amber_outlined` warning, danger `Icons.error_outline` danger, good `Icons.check_circle_outline` success. Title titleSmall, body bodyMedium textMuted, one TextButton right-aligned (`primaryStrong`; `danger` text when the tone is danger). `dense: true` = one 44dp row: icon, one line with ellipsis, a fixed-width TextButton (the chat's `VeilFirstThatFits` fallback). `denseLines` (default 1) lets that line wrap where the height is there: the chat's full notice list passes 2, so "Safety number changed in a group you share" wraps on a 360dp phone instead of ending in "…"; the keyboard rows keep 1. Used only for a decision with an action: safety number changed (in this chat, or in a group you share, dense), a different account under a name, and the safety number page's warnings. Failed sends, a stale device, a failed load or refresh and a sync error are not notices: a glyph on the bubble, a value in a list, a title with Retry, or one muted line with Retry. Decisions use `warn`; `danger` is reserved for failed sends and account holds; `good` is never a notice (it is the verified mark and status text).

### 7.6 VeilBubble (veil_bubble.dart, rename of VeilMessageBubbleCard)
Params `child`, `isMine`, `highlighted`, plus `position: first | middle | last | single` (`VeilBubblePosition`), `failed` and `failedText` (the failed line's words, from the ARB). Width = 78% of the `LayoutBuilder` width (`VeilBubble.widthShare`; the 340 constant is deleted). The bubble sets `DefaultTextStyle` and `IconTheme` for its child, so a child must not read `textTheme.bodyLarge` with its own colour. Fill `primary` (mine) / `surfaceAlt` (theirs). `highlighted` = `surfaceRaised` fill with a 1.5dp `primaryStrong` border inside the same container (the wrapper at message_bubble.dart:66-76 is deleted). `failed` keeps the bubble's own fill; a 20 `Icons.error_outline` in `danger` stands beside it (`VeilBubble.failedGlyphExtent` 26) and a 13sp `danger` line "Not sent. Tap to retry." sits under it, as Signal draws a failed message. Corners 18, the tail-side bottom corner 4 on last/single and 6 on first/middle. No border, no shadow, no gradient, no `AnimatedContainer`.

### 7.7 VeilComposer (veil_composer.dart)
API kept; `leading` defaults to nothing (the padlock at veil_ui.dart:1344-1352 is deleted). Field: `surfaceAlt` fill, radius 18, min 36dp inside a 44dp row, max 5 lines, 12h padding, hint "Message" in textMuted, bodyLarge text, no border. It is built as a 44dp `TextField` (the tap target) with the 36dp `surfaceAlt` pill painted 4dp inside it (`VeilComposer.fieldInset`); a 36dp `TextField` fails the layout gate on every chat case. `trailing` is required. Trailing slot holds the chat feature's `SendButton` (chat/presentation/send_button.dart replaces gradient_send_button.dart): a 32dp `primary` circle with `Icons.arrow_upward` 18 white inside a 44x44 hit area, shown only while the draft is non-empty; with an empty draft it takes no room and slides in with `AnimatedSize` when typing starts. A disabled composer shows its reason as the hint and no send button. The strip sits on canvas with a 0.5dp stroke top, 8h 6v padding.

### 7.8 VeilEmptyState (veil_ui.dart)
API kept including `compact`; `VeilErrorState` becomes `VeilEmptyState.error`. Icon 40 textSubtle with no tile (or no icon), titleLarge (headlineMedium on wide), an optional bodyMedium textMuted line, one secondary or ghost button; `compact` = title + button only. Centred in the remaining space, 32dp side padding. Screens use the title alone ("No contacts yet", "No results", "Couldn't load messages" with Retry): no line explains an empty list. A list that is empty inside a page (blocked accounts, devices) is one bodyLarge textMuted line at the top of the list area, not this widget; an empty chat is one muted line, centred.

### 7.9 Helpers
`VeilHaptics` unchanged. `VeilFirstThatFits` (veil_first_fit.dart) unchanged. `showVeilToast(context, message, {actionLabel, onAction})` = `SnackBar` on `surfaceRaised`, radius 10, text colour, text only (as Signal's, WhatsApp's and Telegram's: no tone icon for success or failure, and no tinted fill); elevation 8 in light, 0 in dark (section 4). An optional text action (Retry). Every toast closes by itself: 4 s, or 8 s with an action (Flutter would keep that one until tapped); with a screen reader on, one with an action waits to be dismissed. The app router takes any toast down when the session locks or signs out, so none shows on the lock screen. `veilToneColor(palette, tone)` maps a tone to its colour (info textMuted, good success, warn warning, danger danger). `veilErrorText(l10n, message)` (veil_error_text.dart) turns a user-facing error into ARB text.

### 7.10 Deleted from the shared layer

| Class (veil_ui.dart lines at e006063) | Refs | Replacement |
|---|---|---|
| VeilHeroPanel (:265-405) | 19 | nothing; the screen opens with its control |
| VeilStatusPill (:681-715) | 74 | `VeilRow.status` text, or inline labelMedium text in bubbles |
| VeilMetricStrip / VeilMetricItem (:788-877) | 9 / 29 | nothing; a value that matters is one row in Security |
| VeilDestructiveNotice (:879-947) | 6 | plain footer text, or `VeilNotice(tone: danger)` where an action exists |
| VeilInlineBanner (:460-551), VeilNoticeRow (:605-679) | 47, 1 | VeilNotice |
| VeilSurfaceCard (:407-436), VeilSectionLabel (:438-458), VeilListTileCard (:949-1038), VeilValueRow (:1692-1736), VeilFieldBlock (:226-263) | 23, 17, 16, 1, 14 | VeilGroup / VeilRow / TextField with labelText and helperText |
| VeilActionCluster (:717-738), VeilActionRow (:740-761) | 9, 2 | Column / Row with SizedBox(8) |
| VeilLoadingBlock (:1487-1558) | 5 | `Center(CircularProgressIndicator(strokeWidth: 2))` sized 20 plus one bodyMedium line |
| VeilSkeletonLine (:1560-1619) | 9 | nothing while loading (the RefreshIndicator spinner is enough) |
| VeilPressable (:146-224) | 1 | NavigationBar |
| VeilCopy / veilKeepWordsWhole (:19-67) | internal | `Text` |
| _BannerPalette / _paletteFor (:553-585, 1738-1754) | internal | palette tone colours directly |
| VeilConversationCard (:1040-1223) | 2 | moved: conversations/presentation/conversation_row.dart `ConversationRow` (section 11.1) |
| VeilStepRow (:1621-1690) | 7 | moved: device_transfer/presentation/step_row.dart `StepRow`: 24dp number disc (primary fill with white digit for the current step, surfaceAlt with textMuted digit otherwise, `Icons.check` for done), titleSmall title, bodyMedium textMuted body, no card |
| VeilBlur (veil_theme.dart:695-738), VeilTypography (:563-646), VeilElevation.raised/chip, VeilMotion.springResponsive/springBouncy, surfaceOverlay/accent/accentSoft/gradients | | deleted |
| gradient_send_button.dart | 1 | chat/presentation/send_button.dart |
| app_router.dart hand-rolled tab bar (:309-440) | | `MainTabShell` in app/router/main_tab_shell.dart using `NavigationBar` (section 8) |

## 8. Bars and navigation

App bar: section 3 (52dp, titleLarge, platform centring, opaque, hairline). Actions are plain IconButtons, at most three; on the chat room: safety (`Icons.verified_user_outlined`, kept until a conversation details screen exists), search, and a menu (`Icons.more_vert_outlined`) with the disappearing timer, Mute notifications or Unmute, and in a 1:1 Report and Block or Unblock (section 16 has the details). The Chats bar: title "Chats" (`navChats`), subtitle only while not connected, actions: new chat (`Icons.edit_outlined`). Contacts bar: add contact (`Icons.person_add_alt_1_outlined`). Settings bar: none.

Tab bar: Material `NavigationBar` through `NavigationBarThemeData`: height 56, `backgroundColor` canvas, `surfaceTintColor` transparent, `indicatorColor` transparent, `overlayColor` transparent, `labelBehavior` alwaysShow, icon 24, label labelSmall (11 / 500), selected icon and label `primaryStrong`, unselected `textMuted`, a 0.5dp stroke top, no ripple (`splashFactory: NoSplash.splashFactory` on the bar), `VeilHaptics.selection()` on change. Tabs: Chats, Contacts, Settings only. From a 1024 px window (a tablet, a desktop) the same tabs are a `NavigationRail` at the start edge through `NavigationRailThemeData`: 80 wide, canvas, no indicator, labels always shown, grouped at the top, the same icons, colours and label style as the bar, a 0.5dp stroke on its trailing edge, no ripple. The phone layout keeps the bar. The two panes of Chats start at a 1120 px window, rail included; with no chat at all the second pane stays plain, since the list already says "No chats yet".

Sheets: `surfaceRaised`, radius top 14, a 36x4 `strokeStrong` drag handle, titleLarge title at 16 padding, rows are `VeilRow`s. The bottom sheet theme sets the handle's colour and size but not `showDragHandle`: a sheet shows its handle only when its call site passes `showDragHandle: true`. No OutlinedButton in a sheet or dialog: in dark its 1dp `stroke` border equals `surfaceRaised` and disappears. Dialogs: `surfaceRaised`, radius 14, titleLarge title, bodyMedium body, TextButton actions (destructive in `danger`). Menus: `surfaceRaised`, radius 10, 44dp items.

## 9. Security facts: the one place each lives

| Fact | The one place | Wording |
|---|---|---|
| End-to-end encryption, and that it is not audited | Settings > Security footer, one line | "The encryption hasn't been independently audited yet." (`securityFooterUnaudited`), or in a development-crypto build "This build uses test encryption. Don't use it for real chats." (`securityFooterTestBuild`) |
| No backup, no recovery, no reset, no admin restore | (a) Before you start, with the checkbox; (b) the confirm bodies of Sign out and Delete account; (c) App lock setup's footer, for the PIN. Nowhere else: not on Choose a handle, Chats, Settings rows, the transfer screens, splash | (a) `onboardingWarnLine2`; (b) "…Your account is gone for good." / "It can't be undone."; (c) "If you forget your PIN, there's no way to reset it." |
| Identity is bound to this device | Before you start | `onboardingWarnLine1` |
| A move signs the old phone out and leaves the messages behind | the old phone's approve dialog, where the move is decided | "Check that your new phone shows {fingerprint}. This phone will then be signed out, and your messages won't move." (`deviceTransferApproveBody`) |
| No phone number, no email, no contact upload | the store listing only (store/play, store/appstore). The app says nothing of it: Choose a handle's one line is `authHandleFindCaption`, "You can't change it later." | |
| Verified contact | the verified mark in the chat bar; "Verified" with a check on the Safety number page and on verified group members | |
| Safety number changed / different account | one `VeilNotice` in the chat (warn), and the Safety number page | |
| Connection state | the Chats title while not connected | "Connecting…", "Offline" |
| App lock, screenshots, app switcher preview, notifications | Settings > Security rows, each a value | "On"/"Off"; "Blocked", or "Not blocked" with "In a chat, the others are told when you take one."; "Hidden"/"Partial"; "On"/"Only while Veil is open" |
| Disappearing messages | the timer glyph + label in the chat bar subtitle, the timer sheet, and one system line in the chat when it changes | "⏱ 1 day" |

TLS pinning, the crypto adapter's name, device integrity, push payloads and the local cache are not shown anywhere (the Security details screen is gone); the lock screen still says when the device looks rooted.

## 10. Copy voice

Rules
1. Plain, short, second person, sentence case. Say what happens, not what the product believes. Never a slogan, never a fragment with a full stop ("No backup. No recovery." is banned), never "This is intentional."
2. The brand is not the subject of a sentence on a routine screen. "Veil cannot/never/does not …" appears only in the privacy notice. "Veil" as a name ("Only while Veil is open", "install Veil") is fine.
3. One idea per sentence; at most two sentences for a helper text; at most one short paragraph anywhere outside the privacy notice.
4. Vocabulary map (apply everywhere, including the web demo, store text and README):

| Was | Now |
|---|---|
| relay, the relay | server (or nothing: "Connecting…") |
| opaque envelope / opaque blob / payload / envelope | encrypted message |
| bind this device / binding / bound / device-bound | create account / this phone / your account lives on this phone |
| trusted device graph / graph summary / graph expansion | (deleted: an account runs on one phone at a time, so nothing lists devices) |
| local barrier / privacy shield | App lock / locked |
| claim code / transfer payload / token / new-device claim | transfer code |
| identity material / secret refs / private material | keys |
| discovery / discovery layer / handle discovery | find (people find you by your handle) |
| peer | contact (or the person's name) |
| conversation (in UI labels) | chat ("Chats", "New chat", "Delete chat") |
| wipe / erase / revoke this device (mixed) | "Sign out" for this phone (the server signs it out, then it is erased); "Delete account" for the account |
| session rejected by the server | Couldn't sign in as @alex |
| Keys: Published | (not shown: the Security details screen is gone) |
| private beta | (deleted) |

5. Before / after examples (ARB key, old, what it is now):
- appTitle: "VEIL" → "Veil"
- authCreateHeroTitle "This device becomes your identity." → key deleted, and the Create account screen with it: the name never leaves the phone, so it lives in Profile under one line, `profileNicknameFooter` "Only you see your name."
- authHandleHeroBody / authHandleFieldCaption "Lowercase. Minimal. Permanent enough to matter." → `authHandleFindCaption` "You can't change it later."; the rules show only as the field's error, naming the one the handle breaks, in the web sign-in's words: `authHandleInvalid` "Use 3 to 32 lowercase letters, numbers, dots or underscores.", `authHandleEdges` "Start and end with a letter or number." or `authHandleRun` "Don't put 2 dots or underscores in a row."
- appLockHeroTitle "VEIL never unlocks itself remotely." → key deleted; the setup screen's one line is `appLockSetupFooter` "If you forget your PIN, there's no way to reset it."
- onboardingWarnTitle "No backup.\nNo recovery.\nNo leaks." → "Before you start"
- onboardingWarnDestructiveBody (any variant) → `onboardingWarnLine2` "If you lose the phone, your account and messages are gone for good."
- settingsSectionDeviceGraph "TRUSTED DEVICE GRAPH" → deleted with the Devices screen (one phone per account; "Move to a new phone" sits in Account, as Signal's Transfer account does); settingsSectionSession "SESSION" → "Account"; settingsSectionPrivacy → "Privacy"; settingsSectionSecurity → "Security"
- conversationsRelayLinked / conversationsCount / conversationsNoBackup "Relay linked · 8 conversations · No backup" → keys deleted
- chatBannerDeliveryStalled "Delivery stalled" + "Retry once the relay is reachable." → key deleted, and every other banner for sending: a failed message says "Not sent. Tap to retry." under its own bubble, and while offline the bar's subtitle reads "Connecting…".
- chatIdentityChangedTitle "Safety number changed" (keep) + body "Nothing is sent to the new key until you review it." → "Nothing is sent until you review it." action "Review"
- chatEmptyBody "Send the first message — it's encrypted end-to-end." → deleted; an empty chat shows `chatEmptyTitle` "No messages yet" and nothing else.
- startDirectHeroBody "There is no graph expansion layer here." → key deleted; New chat has no line under its search field ("Name or handle").
- startGroupHeroBody "Groups are explicit. Add members by handle — VEIL never expands invites through contact graphs." → key deleted; `startGroupMembersCaption` "You can't add members later." (true: no screen adds one)
- chatTtl10sCaption "Strongest ephemerality. Expect the recipient to be looking." → key deleted with the other per-row captions; the sheet has one footer, `chatTtlSheetFooter` "New messages disappear this long after they're sent." (the timer runs from the send, not the read)
- securityStatusAccountRecoveryDetail "No recovery email, reset flow, or admin restore path exists" → deleted with the Security details screen; Before you start says it once.
- deviceTransferTitle "Device Transfer" → "Move to a new phone" on the old phone and `deviceTransferNewTitle` "Move from another phone" on the new one; the "Old phone / New phone" switch is deleted (each side has its own entry).
- safetyNumbersDetailBody (em dash version) → "Check these numbers match {name}'s phone, in person or on a call."
- settingsDeviceNoteStale "recent trusted activity has gone quiet" → deleted, with the Devices screen and every key of it: devices are created only at sign-up and when a move completes, which revokes the old phone in the same transaction, so a real account never had a second device to list.
- Hints: start_direct_chat_screen.dart hint "icarus" → "Name or handle"; start_group hints "Signal Boost" → none (the label says "Group name (required)"), "icarus, daedalus, minos" → "Add a handle"
- Seed and demo names (test/layout/support/layout_seed.dart, web fixtures): ordinary names (Alex Kim, Sam Rivera, Priya Nair, Jonas Weber, Mia Chen, Omar Haddad, Lena Fischer, Tom Walsh); keep exactly one long name for the overflow case ("Alexandra Montgomery-Whitfield").
- Seed messages (the same file, and the Play and iPhone shots drawn from it): short lines as people text them, mostly one line, lowercase starts allowed, each with its own time on Tuesday, April 7, 2026, or for two chats an earlier day (Mia's last night, tom_walsh's on Saturday). The gate and the store art read them at 10:20 that morning (`layoutNow`, put in for `wallClockProvider`), so the morning shows times and the older chats "Yesterday" and "Sat" on any day they run. The long message and the long link sit in Sam's history on Thursday, above a dozen short lines from last night, so no first screen of his chat reaches them at any size and only the chat-room-history case scrolls to them; the account-hold cases show a chat of its own, with only the held account's two locked messages; the conversation-list-search case searches the seeded lines, so its "Messages" part has hits; the handles are picked so that no two neighbouring rows in Chats, Contacts or the Play Chats shot share an avatar colour (the colour comes from the handle, section 6.2: jonask, omar_h and lena_berlin, not jonas, omar and lena); the one notice from the other side ("@priya took a screenshot") is in Priya's chat (chat-room-notices). The Play shots show the natural chat: no link, no notice, no file.
6. Banned words and phrases in UI copy: deliberate, ephemerality, charter, opaque, graph, barrier, binding, relay, payload, envelope, material, "by design", "private by", "not just", "this is intentional", "loss is final", any sentence beginning "VEIL".
7. Titles and labels (final): Chats, Contacts, Settings, New chat, New group, Choose a handle, Before you start, Privacy notice, App lock, Move to a new phone, Move from another phone, Blocked accounts, Safety number, Profile, One-time link, Sign out, Delete account.

## 11. Screen rules (mobile)

Common: every screen is a `VeilShell`; white pages (Chats, Contacts, chat room, New chat, New group, auth, onboarding, privacy notice, lock, Safety number) use `grouped: false`; Settings, Profile, Blocked accounts, App lock setup, both transfer flows and One-time link use `grouped: true`. Each screen copies the stock messenger it is closest to (Signal first, then WhatsApp and Telegram): one title, one line where one is needed, one primary button. A failure is a toast, a field's error, or one line by the control that was used; never a box of explanation.

### 11.1 Chats (conversation_list_screen/phone/pane/parts)
Bar "Chats" with a pencil `IconButton` (New chat); while not connected the title itself reads "Connecting…" or "Offline". No filters, no status line. Search field 44 under the bar; results in "Chats" and "Messages" sections, a section with no hit hidden, the match in bold; no hits: 'No results for "…"'. A failed refresh is one muted line "Couldn't refresh chats" with a ghost Retry above the list. `ConversationRow`: avatar 48, name, when the last message was sent (none on a chat with no message): the time for today, "Yesterday", the short weekday for the six days before ("Sat"), then the short date ("Mar 30", with the year once it is another year), as Signal and WhatsApp do and the web app's Chats row does (`listDate` in apps/web-demo/lib/format.js, whose time is always 12-hour); a message the search found is dated the same way (`MessageTimeFormat.listDate`, read against `wallClockProvider`, the phone's clock) and, when it is the user's own, led by "You: "; preview "You: …" or "{first name}: …" in groups, a system line as its own words; unread badge; a muted chat's bell-off glyph. Empty: "No chats yet" and "New chat". Wide: the empty pane shows "Select a chat" in muted text, also when the list is empty.

### 11.2 Chat room (chat_*)
Bar: avatar 32, name, subtitle "@handle · ⏱ 1 day" (the timer in textMuted) or "Connecting…"; a group's bar says its name and "4 members", as its row does (the conversation list leaves group names out, so the app asks for each group's once per start and shows the members' names only until the answer comes); actions safety number, search, menu. Menu: Mute/Unmute, Disappearing messages (Unblock in its place while blocked), a divider, Report, Block (danger). Above the messages only three notices: safety number changed (with Review), changed in a group you share (dense: its title and Review, the title wrapping to a second line on a narrow phone), and an account hold. Bubbles: meta inside, the time ("9:45 AM", or "09:45" on a phone set to 24-hour time: `MessageTimeFormat.timeOfDay`, the locale's `jm` or `Hm`; the same form in Chats), a timer glyph on a disappearing message, then the status glyph (clock while sending, one outlined check circle sent, two outlined delivered, two filled read with the checks cut out in the bubble's fill, section 5; the words are for screen readers). Failed: section 7.6. A message that did not open shows its reason instead of text, in muted italics after a small padlock: "Waiting for this message"; "Locked until you review the new safety number" after a key change; "Locked until you confirm this account" in a chat held for its handle, whose banner asks for exactly that. Reactions: chips that overlap the bubble's bottom edge, a 2dp canvas-coloured ring, the count only from 2. Long press: a reaction bar above the message and a menu with Report under it. Loading: a spinner. Load failed: "Couldn't load messages" and Retry. Empty: "No messages yet", muted, centred. Search replaces the composer with "2 of 5", "No results" or "Searching…" and up/down arrows; the hit is scrolled to and its words are bold. System lines (screenshot, timer change, members): centred bodySmall textMuted, "You took a screenshot", "You set disappearing messages to 1 day". Errors while the chat is open are toasts.

### 11.3 New chat, New group, One-time link (start_direct_chat_screen, start_group_screen, one_time_link_screen)
New chat: one search field "Name or handle"; rows "New group" and "One-time link"; a "Contacts" header with matching contacts; a typed handle that is not a contact gets one row "Chat with @x", first when no contact matches the text and after the contacts when one does ("rivera" is Sam Rivera's name before it is a stranger's handle); Go opens the first row. Not found is a toast. New group: Name, Description, Members; a typed handle becomes a chip on space, comma or Return; the field counts members; "You can't add members later."; a handle the server doesn't know turns its chip red with "Couldn't find @x". One-time link (from New chat only): the text area, "Add a passphrase" switch, the passphrase field when on, one footer "It opens once, for whoever opens it first.", "Create link"; after it, "Copy link", the expiry line, and the passphrase line.

### 11.4 Contacts (contacts_screen, contact_sheets)
White page. Search field, then one run of rows in name order with no letter headers (avatar 40, name, @handle; an account with no name is its "@handle" alone, here, in New chat and in the contact sheet). A failed refresh is one muted line "Couldn't refresh contacts" with Retry above the list. Empty: "No contacts yet" and "Add contact"; a search with no hit: "No results". Add sheet: title, "Handle" with a fixed "@", "Nickname (optional)", "Add"; no helper, no footer; a handle the server doesn't know is the field's error "Couldn't find @x". Actions sheet: the contact, then Message, Edit nickname, Remove contact, Report, Block (only Block in danger). Nickname sheet: title, field with "Only you see this." under it, Save.

### 11.5 Settings (settings_screen, settings_danger_zone)
Grouped page, one centred column of at most 600 on wide screens. Profile row (avatar, name, @handle, chevron, no value). Appearance: "Theme" with its value; a tap opens a sheet of Light, Dark, System with a check. Privacy: "Send read receipts" (one line under it), "Send typing indicators", "Blocked accounts" (the count when above 0). Security: App lock (On/Off; a tap turns it on while off), Lock now, Screenshots, App switcher preview, Notifications (values, not tappable), and one footer line (section 9). Account: "Move to a new phone", then "Sign out" and "Delete account", both red (Signal's Account page: Transfer account, then Delete account). No Devices row or screen: an account runs on one phone at a time, so the list could only ever hold this one. Sign out is the server-confirmed revoke of this phone and then the erase; if the server doesn't confirm, nothing is erased and a toast says so. Both dialogs ask for the user's own handle ("Type @alex to confirm."), compared without case or "@".

### 11.6 Profile (profile_screen)
Grouped page. Avatar 72, name, "@alex" centred; a tap on the handle copies it ("Handle copied"). One group "Name" with the field (hint "Optional"); "Save" in the bar while the name changed; footer "Only you see your name."

### 11.7 Blocked accounts (blocked_accounts_screen)
There is no Devices screen (section 11.5). Blocked accounts: rows with name and @handle, or "@handle" alone, and an inline Unblock; empty: "No blocked accounts" at the top of the list.

### 11.8 Safety number (safety_numbers_screen, safety_number_cards)
White page. Person row: avatar 56, name, @handle, "Verified" with a check in success or "Not verified" in textMuted. The 12 groups of 5 digits in tabular figures, then one sentence "Check these numbers match {name}'s phone, in person or on a call.", "Verified Nov 16, 2026" when verified, "Mark as verified" while not, then one row of two text buttons "Copy my code" and "Paste their code" (no QR code: no app here scans one), and "Renew keys" as a quiet button at the bottom, once there is a number (with none there is no session to renew). Identity change: the notice first, the person, "New safety number" over the new digits, the sentence, "Verify the new number" (or "Accept new number"; "Keep the old one" where declining is allowed), the two text buttons. Changed in a group you share: the notice "Changed in a group you share" / "Review it there first." / Review, then "Number before the change" over the pinned digits, and nothing that would confirm the old key. Group: a row per member, "Verified" with a check only on verified members, no footer; empty: the title alone.

### 11.9 App lock (app_lock_screen, app_lock_parts)
Lock state (white page, no bar): "Veil is locked", the PIN field (centred digits over a line, no box, as Signal's PIN entry: a filled box read as a second button over the disabled "Unlock"), "Unlock", and a text button naming the method ("Use Face ID", "Use Touch ID", "Use fingerprint"); the biometric prompt opens by itself once the screen is up. Lockout and compromised-device states are one line under the field. Setup (grouped page "App lock"): "PIN" and "Confirm PIN", footer "If you forget your PIN, there's no way to reset it.", "Turn on". When opened from Settings the bar has a back button that cancels (no PIN exists yet); the lock the app engages by itself has no way back.

### 11.10 Choose a handle (choose_handle_screen)
The signed-out home (Create account is gone). One field with a fixed "@", the line "You can't change it later." under it, "Create account" (a spinner and "Creating account…" inside it while it works), and a ghost "Move from another phone". A character no handle can have, or more than 32, is the field's error as it is typed, and "Create account" stays off. Too short, a dot or underscore at either end, or two in a row may be on the way to a good handle, so they show only when the handle is submitted, naming the rule it breaks as the web sign-in does (`handleRuleBroken`, issued_handle.dart).

### 11.11 Before you start (onboarding_warning_screen)
White page, no bar. "Before you start", then the facts as plain bodyLarge sentences with no icons, the checkbox, and "Continue" pinned at the bottom, enabled by the checkbox.

### 11.12 Privacy notice (privacy_consent_screen)
A white document page: small bold headings, paragraphs 8 apart, a hairline above the pinned controls, the agreement as a `CheckboxListTile` with no card, "Agree and continue".

### 11.13 Moving the account (device_transfer_screen and its panels)
Each side is its own flow, picked from the session (a signed-in phone is the old one): no switch between phones, no stepper. Old phone ("Move to a new phone", from Settings): three numbered lines as plain text and "Get code"; then "Enter this code on your new phone", the whole code in bodyLarge, selectable with a long press: the session on one line ending "::" and the token on the next (two UUIDs, each fitting a phone's width whole, so neither breaks where it is read off), without the `VEIL_TRANSFER::` prefix the copied code starts with; no box, no monospace, no tracking, so it can be read off and typed as well as copied; "Copy code" copies all of it on one line, prefix included; the new phone takes it with or without the prefix, and with the line break or any spaces typed in, since no id holds one, an outlined "Copy code", a grey "Expires in 4 minutes", the field "Code from your new phone" and "Approve". Approve reads the claim first and asks "Move your account to the new phone?" with the key fingerprint the new phone shows (Cancel / Move account); only then is the approval signed. After it: "Approved. Finish on your new phone." New phone ("Move from another phone", from Choose a handle): "Transfer code" (hint "Paste the code from your old phone"), "Device name", and one "Continue" that reads the code and registers the phone; then "Approve on your old phone" with the claim code to type there, centred (`TransferClaimCode`: the relay's claim id, a UUID of 36 characters, in `monospace` at headlineMedium 400 with tracking 0, wrapping only after a hyphen so no group of it splits; a screen reader reads it whole; the layout case `device-transfer-new-device-approve` draws a real one), "Enter this code on your old phone.", the key fingerprint and expiry in small grey lines, "Finish", and "Change" to go back to the first screen. Done: a toast "Your account is on this phone now." and Chats.

### 11.14 Splash and lock overlay (splash_screen, veil_app.dart)
Splash: canvas with the brand mark; a 20dp spinner appears only after one second; no text. The app-switcher privacy overlay: canvas with the brand mark only.

## 12. Web demo (apps/web-demo)

Prerequisite, done before the restyle: every Korean literal in index.html (66 lines), s.html (21), src/ (about 325 across the files listed in section 15) and the emoji glyphs are replaced by English `data-i18n` keys or English literals before the restyle; ko.json and ja.json are deleted; `<html lang="en">`; manifest `lang` en and an English description.

### 12.1 Tokens (app.css :root and .theme-light)
Dark (the theme follows the browser unless one is chosen in Settings): `--bg #000000; --bg-grouped #000000; --bg-elev #1C1C1E; --bg-alt #26262B; --bg-raised #2C2C2E; --line #2C2C2E; --line-strong #3A3A3C; --fg #F2F2F7; --fg-muted #9A9AA1; --fg-subtle #8E8E93; --primary #2A63CC; --primary-strong #6FA3FF; --primary-soft rgba(111,163,255,.16); --danger #FF6B5E; --warn #FF9F0A; --good #30D158; --bubble-mine #2A63CC; --bubble-mine-meta #E3ECFB; --bubble-theirs #26262B`.
Light (`.theme-light`): `--bg #FFFFFF; --bg-grouped #F2F2F7; --bg-elev #FFFFFF; --bg-alt #E9E9EB; --bg-raised #FFFFFF; --line #C6C6C8; --line-strong #AEAEB2; --fg #000000; --fg-muted #5F5F64; --fg-subtle #8E8E93; --primary #1F5FD6; --primary-strong #1F5FD6; --primary-soft rgba(31,95,214,.12); --danger #B8000E; --warn #9A4600; --good #15683A; --bubble-mine #1F5FD6; --bubble-mine-meta #DCE7FB; --bubble-theirs #E9E9EB`.
Radii: `--r-sm 6px; --r 10px; --r-lg 14px; --r-bubble 18px`. Font: `--font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif` (Pretendard and Apple SD Gothic Neo removed); `--mono` unchanged. Shadow: `--shadow-modal: 0 8px 24px rgba(0,0,0,.18)` in light only, used by `.dialog` and `.menu`; `--shadow-glow`, `--shadow-2` and every other box-shadow deleted. Type: body 15px/1.4; titles 17px/600; meta 11px; labels 13px; sentence case; `text-transform` never. Delete the gradients at app.css:61, :97, :269, :418, :1241, :1248, the pulse keyframes (:1152), the skeleton shimmer, `backdrop-filter` (:102), the beta-banner block and `--banner-h`, the `content: " ▾"` summaries (:357, :361) in favour of a plain text button. The KakaoTalk import stays, restyled with the same tokens.

### 12.2 Shell
List bar 52px, `--bg`, 0.5px `--line` bottom and right, over the list's column only; the open chat's own bar heads the other column on the same line (Signal Desktop, WhatsApp Web, Telegram Web: one bar and one ⋮ over each column, never two stacked). On a phone with a chat open the list bar is hidden and the chat bar leads with a back chevron (`#back-to-list`). Left: the title "Chats" 17/600, and under it "Connecting…" or "Offline" in 12px `--fg-muted` only while that holds; nothing while connected (no mark tile, no `.topbar-pill`). Right: the compose icon (`compose`, tooltip "New chat (Ctrl+N)", "(⌘N)" on a Mac), split view, ⋮, each a 44px sprite icon button. Sidebar 320px on `--bg`: the search field first (44, `--bg-alt`, radius 10, placeholder "Search"), then rows 64px: `.avatar` 40 solid, name 16/600, snippet 13 `--fg-muted`, time 11 (the days as the phone's Chats row writes them, section 11.1: "9:45 AM", "Yesterday", "Sat", "Mar 30"; `listDate`), unread badge `--primary` pill white 12/600, 0.5px inset hairline at 68, active row `--bg-alt`. No account row and no full-width New chat button in the sidebar: the account heads the ⋮ menu. Empty list: "No chats yet" and a small "New chat" button; no results: 'No results for "…"'. The notification offer ("Turn on notifications", "Not now" / "Turn on") sits above the list once the user has sent a message. Conversation tabs across the panel top (40px, label 13, active = 2px `--primary-strong` underline) show only while two or more chats are open. The empty pane is one muted line, "Select a chat". Chat header 52px: avatar 32, name, verified check in `--good`, a bell-off glyph in `--fg-muted` while muted, "typing…" under the name only while typing (no "Online": peers never learn presence); actions: search, the shield (Safety number) and ⋮. The ⋮ menu holds "Mute notifications" (1 hour, 8 hours, 1 week, Always) or "Unmute", a divider, then in a 1:1 "Report…" and "Block…", and "Clear chat history…"; Block and Clear are `--danger`. With the peer blocked (as mobile): "Unblock" follows the mute item, no Block is offered, and the composer's place holds "You blocked @sam." with an Unblock text button (no confirm; whom the account blocked is asked once a session). The app's ⋮ menu opens under its own button. No trash or bell in the header and no `window.prompt` anywhere. Toasts (`src/ui/toast.js`) sit top centre on `--bg-raised` and are text only, with at most one text action: no check or warning icon; an error is an `alert` for screen readers and stays 5 s. A toast never carries the browser's or the server's words: a chat list refresh that fails offline or on the network shows none (the bar's "Offline" or "Connecting…" says it), any other failure says "Couldn't refresh chats" (`conv.refreshFailed`, mobile's words).

### 12.3 Messages and composer
Bubbles max-width 72%, padding 8px 12px, radius 18 with 4px tail corner, mine `--bubble-mine` white text, theirs `--bubble-theirs` `--fg`; meta 11px inside the bubble: the time and, on our own messages, one glyph (a clock while waiting; Signal's check circles: `tick-sent` one outlined, `tick-delivered` two outlined, `tick-read` two filled with the checks cut out in `--bubble-mine`). The state's word is for assistive technology only. A message that cannot be opened shows its reason in `--fg-muted` italics (`.msg-locked`): "Waiting for this message", "Locked until you review the new safety number", "Locked until you confirm this account" (a chat held for its handle), "Couldn't decrypt this message". Reply quote as a 2px `--line-strong` left rule with 13px `--fg-muted` text; reactions as 28px chips `--bg-alt` radius 14 ringed 2px in `--bg`, overlapping the bubble's bottom edge by 6px on the side away from its tail, the count only from 2, own = `--primary-soft`; a file is a card: icon, name, "TXT · 2.3 MB" and a download glyph. Day divider 13/500 `--fg-muted` centred, no rule; system notices 13 `--fg-muted` centred. An empty chat says "No messages yet" in muted text, nothing else. Composer strip `--bg` with 0.5px `--line` top; field `--bg-alt` radius 18 min 36px max 5 lines, placeholder "Message"; attach, image and voice as 44px sprite icon buttons (`paperclip`, `image`, `mic`); send = 32px `--primary` circle with `arrow-up`, visible only with a draft. A reply or an edit puts a bar above the field ("Reply to @sam" or "Editing message", the quoted text, ✕); Enter saves an edit, Esc drops it; either way the unsent draft (and its reply quote) set aside when the edit began comes back. Search in a chat: placeholder "Search this chat", count "1 of 2" or "No results".

### 12.4 Sprite, avatars, dialogs, menu, auth, s.html
Sprite (inline `<svg>` symbols at the top of index.html and s.html; 24 viewBox, stroke 1.75, round caps): back, search, more, split, compose, bell, bell-off, shield, paperclip, image, mic, arrow-up, check, tick-sent, tick-delivered, tick-read, close, copy, warning, user, reply, chevrons, clock, file, download. `dom.js` `avatarFor` returns `.avatar.av-N` with the FNV-1a index from section 6.2 (same hash code in JS), white initial 600 at 0.42em, no gradient, no presence dot; sender names in group threads use `.name-N` from 6.3. Dialogs: `--bg-raised`, radius 14, 1px `--line`, `--shadow-modal` light only, title 17/600 (a question whose verb the OK button repeats: "Block @sam?" / "Block"), body 15 `--fg-muted`, actions as text buttons (danger ones in `--danger`); a confirmation may carry a safe alternative between Cancel and OK (Sign out offers "Move to another device"). Menu (⋮ in the bar): the account first (avatar, @handle, a copy button: "Handle copied"), then "Settings", "Keyboard shortcuts", "Move to another device…", "Import from KakaoTalk…", a divider and "Sign out…" in `--danger`; no icons, no connection or sounds items. A menu item that opens a dialog ends with "…". Settings dialog: sections under 13px `--fg-muted` headers: Appearance (Theme: System, Light, Dark; System is the default and follows the browser), Notifications (the permission row "Web notifications", not the sheet's W6 "Notifications", so it does not repeat the section header above it: "Allow" until asked, then its state; "Show"; "Sounds"; one footer line), Blocked accounts (rows with Unblock, or "No blocked accounts"); "Done". Keyboard shortcuts: two groups, Navigation and Messages, keys as the platform writes them (⌘ on a Mac, Ctrl elsewhere), "Done". Report dialog: the seven reasons in the mobile order, one line on what the report carries, "Also block @x" ticked, Cancel / Report. Auth screen: a left-aligned column max-width 360 on `--bg`; "Veil" 22/600, no tagline and no explainer; "Choose a handle" (input 44 `--bg-alt` radius 10, placeholder "alex", hint "You can't change it later."; what is wrong with the handle, whether missing, against one of the server's rules or taken, replaces the hint in `--danger` until the handle changes, never a toast), "Create account" primary 48, "Move from another device" as an outlined 48 button, and one 13px `--fg-muted` footer line about the missing backup. A saved account is a 64px row (avatar 40, "Saved account", @handle, "Continue"), with a small red text action "Remove @x from this browser" under it, shown only while something is stored; a refused one shows one notice with "Remove from this browser" and "Try again" instead. Key-change banner, account-hold banners, legacy banner and the notification offer: `--bg-alt` radius 10 notice with a sprite icon in the tone colour and text-button actions. Move dialogs: three numbered lines, the code in a one-line read-only field with a primary "Copy code" button, the fingerprint with one check line, and "Approve" behind a confirmation. s.html (one-time link page): same tokens, no pill row, no emoji; compose: "One-time link", the field (its "Secret" label for screen readers only), "Add a passphrase", "Create link", one footer line; view: "Someone sent you a secret", one line, a 48 primary "Reveal"; once revealed, "Secret" over the text and one line; the "gone" state is one line. Its words live in s.html and s.js, not i18n/en.json, because a production server serves only the page and its modules. icon.svg: flat `#1F5FD6` rounded square (rx 22%) with the white mark from section 13; manifest `theme_color` and `background_color` `#000000` with `color-scheme: light dark` honoured.

## 13. Brand mark, launcher, splash

Mark: a white "V" drawn as two straight strokes of equal weight (stroke = tile width / 9, round caps, the V spans 52% of the tile width and sits optically centred). No gradient, no second colour, no wordmark. Launcher: iOS 1024 PNG with the mark on flat `#1F5FD6`; Android adaptive foreground = white mark on transparent, `adaptive_icon_background` `#1F5FD6`; `background_color_ios` `#1F5FD6`; android/app/src/main/res/values/colors.xml `ic_launcher_background` `#1F5FD6`. Splash (`flutter_native_splash`): `color` `#FFFFFF` and `color_dark` `#000000`, `image` = the mark in `#1F5FD6` 96dp on transparent (same file for both; `image_dark` identical), no `branding`, `android_12` same values, `fullscreen` false. `splash_branding.png` and `app_icon_rounded.png` are deleted. The in-app splash and the privacy overlay draw the same mark as a Flutter `CustomPaint` (no PNG).

## 14. Accessibility and the gates

- Contrast unit test (apps/mobile/test/theme/veil_palette_contrast_test.dart): for both palettes assert at 4.5:1 or more: `text` and `textMuted` on canvas, canvasAlt, surface, surfaceAlt; `textMuted` on surfaceRaised; `primaryStrong` on canvas, canvasAlt, surface, surfaceAlt; white on `primary`; `danger`, `warning`, `success` on canvas, surface, surfaceAlt; the outgoing meta colour on `primary`; white on each of the 8 avatar colours; each light name tint on #E9E9EB and each dark name tint on #26262B; white on the neutral group discs; `primaryStrong` on `primarySoft` composited over canvas and surface. Assert at 3:1 or more: `textSubtle` on canvas and surface; each avatar colour against canvas and surface in both modes. The test fails the build on the next palette edit that regresses.
- Layout gate (`flutter test test/layout`): English only, three phone sizes, light render at 390x844 in English; known_phone_layout_failures.dart may only shrink, and it is empty: a screen that stops fitting is fixed, not listed. Tap targets 44 everywhere (section 4).
- Goldens: test/ux_review_golden_test.dart is regenerated only when the chat screens change on purpose.
- Semantics: every `VeilRow`, `ConversationRow`, bubble and button keeps its label; `VeilAvatar` is excluded; state is always also text (ticks have "Read", status has a word, never colour alone).
- Larger text: bars clamp at 1.3; rows grow; the chat keeps 45% for messages (gate).

## 15. Removed (the explicit list)

Mobile: VeilHeroPanel, VeilStatusPill, VeilMetricStrip, VeilMetricItem, VeilDestructiveNotice, VeilInlineBanner, VeilNoticeRow, VeilSurfaceCard, VeilSectionLabel, VeilListTileCard, VeilValueRow, VeilFieldBlock, VeilActionCluster, VeilActionRow, VeilLoadingBlock, VeilSkeletonLine, VeilPressable, VeilCopy, veilKeepWordsWhole, VeilBlur, VeilTypography, VeilElevation.raised/chip, VeilMotion.springResponsive/springBouncy, VeilPalette.accent/accentSoft/surfaceOverlay/primaryGradient/surfaceGradient, GradientSendButton, the hand-rolled tab bar, the shell gradient and three blobs, every BoxShadow and LinearGradient in lib/, every `_rounded` icon, every `.toUpperCase()`, the composer padlock, the conversation list status line, the "VEIL" title and wordmark, Pretendard, splash_branding.png, app_icon_rounded.png, the 6 switched-off feature directories (ai, calls, media, stickers, stories, voice) and attachment_preview_screen.dart, app_ko.arb and its generated class, the Korean layout-gate files, about 130 ARB keys (every key matching Eyebrow, Pill, pill, Metric, HeroTitle, HeroBody, PrivateBeta) plus splashBody, settingsGraphSummary, settingsNoRecoveryPath, conversationsNoBackup, conversationsRelayLinked, conversationsRelayIdle, conversationsCount, conversationsRelayConnectedBody, conversationsRelayIdleBody, conversationsActiveBody, startDirectAwaitingInput, startDirectBannerTitle, startDirectBannerBody, authCreateRestoreTitle, authCreateRestoreBody, authHandleBindingSection, authHandleStep1Title…authHandleStep4Body, appLockNoRecoveryBody, appLockCompromisedTitle (becomes body-only), chatLegacyUnverifiedBadge (replaced by a sentence key), the 29 attachment* keys, 11 calls* keys, 2 ai* keys, navCalls, navStories, conversationsPreviewCall, conversationsKindCall, and any key no Dart file references after the screen packages land.
Web: the beta banner, the brand mark tile, the topbar pill, gradients, glows, shimmer, pulse, emoji glyphs and emoji in strings, the language switcher and `?lang=`, ko.json, ja.json, the presence dot, the avatar gradients, Pretendard in the font stack, the "VEIL · Private Beta" OG and Twitter meta.
Docs and public copy: README badges, the slogan blockquote, "not just X — it is Y" and "That tradeoff is the product" phrasing, em dashes, the store features line that listed a Korean UI (store/appstore/metadata-en.txt:28, store/play/full-en.txt:27), the locale list that named Korean and Japanese (docs/app-store-listing-metadata.md:10), the Korean store texts and the Korean Play screenshots, docs/design-light-theme.md, the previous docs/mobile-design-system.md. The Korean guides under docs/, the Korean privacy policy and the Korean half of site/index.html stay, by the owner's decision.

## 16. Where the code departs from this document

Each of these was found while building to the sections above and is how the code works; the section it amends defers to it.

- Text fields: `contentPadding` 12h 11v, not 10v; a field that must be 44 is dense (section 4).
- Composer: a 44dp `TextField` with the 36dp pill painted 4dp inside it (section 7.7).
- Bars: the 0.5dp hairline is painted over the bar's last half point; the tab bar's top hairline likewise (section 4).
- `VeilShell` body: no `ColoredBox`; the scaffold paints the page colour (section 7.1). `VeilRow` draws its ink on its own transparent Material.
- `VeilElevation.modal` is the specification of the one shadow; the themes draw it as Material elevation 8 with shadow colour 0x2E000000 in light and 0 in dark (section 4). The light `SnackBar` keeps elevation 8.
- `Switch.adaptive` on iOS ignores the Material switch theme and draws system green; the theme registers an adaptation so the track is `primary` there too. Disabled switches: on = `primary` at 38% alpha with a white thumb, off = `surfaceAlt` track with a `textSubtle` thumb (section 7.2).
- Dark sheets: the 0.5dp `strokeStrong` line runs along the top edge only (section 4).
- `VeilGroup` in a sheet, dialog or menu: no container, `strokeStrong` hairlines in dark (section 7.2).
- Drag handles: shown only where the call site passes `showDragHandle: true` (section 8).
- `ThemeData.materialTapTargetSize` is `padded` everywhere. `RefreshIndicator` and text selection use `colorScheme.primary`; pass `palette.primaryStrong` at the call site where brand text colour is wanted.
- Disabled FilledButton: `textSubtle` on `surfaceAlt` (2.69:1). WCAG exempts disabled controls; it stays.
- Test fonts: Roboto Regular stands in for `monospace`; there is no RobotoMono (section 3).
- Chat bar (section 8): the actions are the safety number, search and a menu (`Icons.more_vert_outlined`, 44dp text items with no glyph, as WhatsApp's), each button 44 square (not Material's 48, so a verified "Sam Rivera" fits at 360 beside them): Mute notifications or Unmute, Disappearing messages (Unblock in its place while the peer is blocked: nothing can be sent there), a divider (`stroke` in light; `strokeStrong` in dark, where `stroke` is the menu's own fill), Report, and Block (in `danger`). The timer still shows in the bar's subtitle while one is set. A 1:1 whose peer is blocked shows one bodyMedium textMuted line, "You blocked @sam.", with an Unblock TextButton in the composer's place. A muted chat's row in Chats shows `Icons.notifications_off_outlined` at 14 in textMuted on its second line, and its unread badge (if any) is textMuted with the count in the page colour (6.35:1 light, 7.51:1 dark).
- Copy that differs from section 10's examples, each for a reason given there: `chatTtlSheetFooter` (the per-row `chatTtl*Caption` family is gone; one footer says "New messages disappear this long after they're sent."), `startGroupMembersCaption` (one sentence, "You can't add members later."). `authCreateFieldCaption`, `deviceTransferChip*` and `chatEmptyEncrypted` are deleted.
- The two account dialogs (Sign out, Delete account) ask for the user's own handle, compared without regard to case or the "@"; there is no Wipe or Revoke row (Sign out is the server-confirmed revoke).

## 17. Never reintroduce

On either platform, in any file:

1. A second brand colour, any violet or purple (#8B5CF6, #6E56F8, #8B7BFF, #A99CFF, #BF5AF2, #AF52DE, #6C8EFF, #B06CFF), any gradient (LinearGradient, RadialGradient, CSS linear-gradient or radial-gradient), any glow or BoxShadow outside the one modal shadow on dialogs, sheets and menus in light mode, any BackdropFilter or backdrop-filter, any haze or blob behind content.
2. `primary` or `primaryStrong` outside the uses of rule 1: no blue icons in rows, blue section headers, blue app bar, blue verified mark, blue borders or blue avatars.
3. Tracked or upper-case labels: letterSpacing above 0, `.toUpperCase()`, `text-transform: uppercase`, small caps, an eyebrow or kicker above a card or a screen, a label that repeats the screen title.
4. Hero or slogan openers: a sentence with a full stop as a headline, a paragraph before the first control, "No backup. No recovery. No leaks.", "This device becomes your identity.", "This is intentional.", "Private by design", "Device-bound".
5. Pills that restate fixed facts ("E2E encrypted", "No recovery", "Local only", "Private beta"); any status pill with a fill or a border. State is a word in a tone colour (labelMedium) or a glyph. The only pills are the unread badge, the switch, the avatar and the send circle.
6. Metric or KPI tiles (label over value), status strips ("Connected · 8 chats · No backup"), dashboards of static values, counts the list already shows.
7. Tinted alert boxes with coloured borders, red "destructive" cards, a notice for information, a security fact in more places than section 9 allows, "Veil cannot/never/does not" outside the Security footer and the privacy notice.
8. Cards inside cards, a field inside a card, a list row as a floating card, a radius above 18 (except the pill shapes), 2 to 3 px gaps between rows, a second rounded container around a bubble.
9. Gradient or glowing avatars, presence dots, a ring on an avatar, `String.hashCode` for the avatar colour, a letter on a group avatar, a second avatar implementation.
10. Icons: any `Icons.*_rounded`, `radar_outlined`, `priority_high`, `gpp_maybe`, a padlock in or near the composer, a shield as decoration, emoji as icons or in UI strings, mixed icon families.
11. Type: a bundled UI font in production, a second type scale, display sizes above 28, tracking tighter than -0.3, Title Case titles, "VEIL".
12. Copy: em or en dashes, slogans, "not just X, it is Y", "that tradeoff is the product", the words relay, opaque, envelope, payload, binding, barrier, graph, material, discovery, ephemerality, deliberate and charter in UI text, mythological or aristocratic demo names, the brand as the subject of a sentence on a routine screen, "private beta".
13. Korean or Japanese strings in the app or the web demo, locale switches, `?lang=`, app_ko.arb, ko.json, ja.json, a features line that lists a Korean UI, word-joiner hacks for Hangul wrapping.
14. Skeleton shimmer, glowing loaders, staggered entrance animations, scale-on-press, spring curves other than `springGentle`, a splash that shows text.
15. A hand-rolled tab bar with a pill indicator, a frosted bar, `extendBodyBehindAppBar`, a bar taller than 52dp, bar actions on background tiles.
16. Filled red buttons, danger as a fill, tap targets under 44x44, `textSubtle` for body or placeholder text, `textSubtle` on canvasAlt or surfaceAlt.
17. README badges, a slogan blockquote, store text claiming a language other than English, a listing doc that names other app locales.
18. A screen, route or button for a feature that does not work end to end (calls, a media picker, stickers, stories, a voice recorder, an assistant, sending an attachment); a pill or banner that says attachments are encrypted.
19. A shared widget beyond the eight of section 7 without changing this document first; an ARB key that states a security fact section 9 already placed.
20. A line added to known_phone_layout_failures.dart; weakening the layout gate, the contrast test or the strings gate to get green.
