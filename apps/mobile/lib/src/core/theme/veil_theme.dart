import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// The design tokens and the two themes (docs/mobile-design-system.md). Pages
// are white or black, lists are full-bleed rows with hairlines, the type is
// the platform's own font, and one blue appears in a handful of places.

class VeilSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Nothing is rounder than [xl] but the four pill shapes
/// (avatar, switch, unread badge, send circle).
class VeilRadius {
  /// Filter chips.
  static const double xs = 6;

  /// Segmented controls, menu item hover.
  static const double sm = 8;

  /// Text fields, buttons, group containers, notices, snackbars.
  static const double md = 10;

  /// Dialogs, sheet tops.
  static const double lg = 14;

  /// Bubble main corners, the composer field.
  static const double xl = 18;

  static const double pill = 999;
}

class VeilIconSize {
  static const double xs = 14;
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
  static const double xl = 40;
}

class VeilMotion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve emphasize = Cubic(0.2, 0.8, 0.2, 1.0);
  static const Curve smooth = Cubic(0.4, 0.0, 0.2, 1.0);

  /// The one spring, for sheets.
  static const Curve springGentle = Cubic(0.22, 1.0, 0.36, 1.0);
}

/// The only shadow in the product: under dialogs, sheets and menus, in the
/// light theme only. In the dark theme those surfaces are lifted by their
/// tier ([VeilPalette.surfaceRaised]) and a hairline instead.
class VeilElevation {
  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x2E000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

class VeilPalette {
  const VeilPalette({
    required this.canvas,
    required this.canvasAlt,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.stroke,
    required this.strokeStrong,
    required this.primary,
    required this.primaryStrong,
    required this.primarySoft,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.outgoingMeta,
  });

  /// The page of Chats, Contacts, the chat room, auth, onboarding and the
  /// lock screen.
  final Color canvas;

  /// The page of grouped screens (Settings, Profile, Security, ...). The
  /// same as [canvas] in the dark theme.
  final Color canvasAlt;

  /// Group containers on a grouped page, list rows, bars.
  final Color surface;

  /// Incoming bubbles, field fills, disabled fills, notice fills.
  final Color surfaceAlt;

  /// Sheets, dialogs and menus.
  final Color surfaceRaised;

  /// 0.5dp separators, the bar hairline, a field's border at rest.
  final Color stroke;

  /// A focused field's border, the sheet drag handle, separators inside a
  /// dark group.
  final Color strokeStrong;

  /// The brand fill: filled buttons, own bubbles, the switch track, the
  /// send circle, the unread badge, the launcher tile. Nothing else.
  final Color primary;

  /// The brand as text: the active tab, text buttons and links, the
  /// focused floating label, progress indicators, a selected segment's
  /// label. Nothing else.
  final Color primaryStrong;

  /// The fill of a selected segment, filter chip or own reaction.
  final Color primarySoft;

  final Color text;

  /// Subtitles, meta, headers, footers, notice bodies, placeholders.
  final Color textMuted;

  /// Disabled text, chevrons and disabled glyphs only: never body or
  /// placeholder text, never on [canvasAlt] or [surfaceAlt].
  final Color textSubtle;

  /// The verified mark and "Verified" / "Available" status text.
  final Color success;

  /// Warn notice icons, stale status text, the timer glyph in a bar.
  final Color warning;

  /// Destructive row titles and text buttons, "Not sent", danger notice
  /// icons. Never a fill.
  final Color danger;

  /// Time and ticks inside an own bubble (on [primary]).
  final Color outgoingMeta;

  @Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. There is one brand colour: primary.')
  Color get accent => primary;

  @Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use primarySoft.')
  Color get accentSoft => primarySoft;

  @Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use surfaceAlt.')
  Color get surfaceOverlay => surfaceAlt;

  static const dark = VeilPalette(
    canvas: Color(0xFF000000),
    canvasAlt: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceAlt: Color(0xFF26262B),
    surfaceRaised: Color(0xFF2C2C2E),
    stroke: Color(0xFF2C2C2E),
    strokeStrong: Color(0xFF3A3A3C),
    primary: Color(0xFF2A63CC),
    primaryStrong: Color(0xFF6FA3FF),
    primarySoft: Color(0x296FA3FF),
    text: Color(0xFFF2F2F7),
    textMuted: Color(0xFF9A9AA1),
    textSubtle: Color(0xFF8E8E93),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF6B5E),
    outgoingMeta: Color(0xFFE3ECFB),
  );

  static const light = VeilPalette(
    canvas: Color(0xFFFFFFFF),
    canvasAlt: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE9E9EB),
    surfaceRaised: Color(0xFFFFFFFF),
    stroke: Color(0xFFC6C6C8),
    strokeStrong: Color(0xFFAEAEB2),
    primary: Color(0xFF1F5FD6),
    primaryStrong: Color(0xFF1F5FD6),
    primarySoft: Color(0x1F1F5FD6),
    text: Color(0xFF000000),
    textMuted: Color(0xFF5F5F64),
    textSubtle: Color(0xFF8E8E93),
    success: Color(0xFF15683A),
    warning: Color(0xFF9A4600),
    danger: Color(0xFFB8000E),
    outgoingMeta: Color(0xFFDCE7FB),
  );

  /// Resolve the palette matching a [Brightness]. Screens should prefer
  /// `context.veilPalette` which reads the brightness from [Theme.of].
  static VeilPalette forBrightness(Brightness brightness) => brightness == Brightness.light ? light : dark;
}

class VeilTheme {
  /// The dark theme. [fontFamily] is null in production: the text theme
  /// keeps Flutter's platform families, so iOS draws its system font and
  /// Android draws Roboto. The test harness passes the family it loaded.
  static ThemeData dark({String? fontFamily}) => _build(VeilPalette.dark, Brightness.dark, fontFamily);

  /// The light theme; see [dark].
  static ThemeData light({String? fontFamily}) => _build(VeilPalette.light, Brightness.light, fontFamily);

  static ThemeData _build(VeilPalette palette, Brightness brightness, String? fontFamily) {
    final light = brightness == Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: Colors.white,
      secondary: palette.primary,
      onSecondary: Colors.white,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.surface,
      onSurface: palette.text,
      onSurfaceVariant: palette.textMuted,
      outline: palette.stroke,
      outlineVariant: palette.strokeStrong,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.text,
      onInverseSurface: palette.canvas,
      inversePrimary: palette.surfaceRaised,
      surfaceContainerHighest: palette.surfaceRaised,
      surfaceContainerLow: palette.surfaceAlt,
      surfaceContainer: palette.surfaceAlt,
      surfaceContainerHigh: palette.surfaceRaised,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      dividerColor: palette.stroke,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      adaptations: <Adaptation<Object>>[_VeilSwitchAdaptation(palette)],
    );

    // The scale sits on the platform's text theme (which carries the
    // platform's font family) so the names of the fonts stay Flutter's.
    // Every style sets its height, so line boxes are font-independent, and
    // its tracking, so nothing is spaced out.
    final textTheme = base.textTheme
        .merge(
          const TextTheme(
            headlineLarge: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.3),
            headlineMedium: TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.2),
            titleLarge: TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.2),
            titleMedium: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.1),
            titleSmall: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0),
            bodyLarge: TextStyle(fontSize: 16, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0),
            bodyMedium: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0),
            bodySmall: TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w400, letterSpacing: 0),
            labelLarge: TextStyle(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0),
            labelMedium: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0),
            labelSmall: TextStyle(fontSize: 11, height: 1.2, fontWeight: FontWeight.w500, letterSpacing: 0),
          ),
        )
        .apply(bodyColor: palette.text, displayColor: palette.text);

    final titleLarge = textTheme.titleLarge!;
    final titleMedium = textTheme.titleMedium!;
    final bodyMedium = textTheme.bodyMedium!;
    final bodySmall = textTheme.bodySmall!;
    final labelLarge = textTheme.labelLarge!;
    final labelMedium = textTheme.labelMedium!;
    final labelSmall = textTheme.labelSmall!;

    final mutedBodyMedium = bodyMedium.copyWith(color: palette.textMuted);
    final mutedBodySmall = bodySmall.copyWith(color: palette.textMuted);

    RoundedRectangleBorder rounded(double radius) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder fieldBorder(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: textTheme,
      iconTheme: IconThemeData(color: palette.textMuted, size: VeilIconSize.md),
      // The bar: 52dp, opaque, the title in titleLarge, centred on iOS and
      // at the start on Android (centerTitle is left to the platform).
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: palette.text,
        titleTextStyle: titleLarge,
        toolbarTextStyle: bodyMedium,
        iconTheme: IconThemeData(color: palette.textMuted, size: 24),
        actionsIconTheme: IconThemeData(color: palette.textMuted, size: 24),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: rounded(VeilRadius.md),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: bodyMedium,
        behavior: SnackBarBehavior.floating,
        elevation: light ? 8 : 0,
        shape: rounded(VeilRadius.md),
        actionTextColor: palette.primaryStrong,
        closeIconColor: palette.textMuted,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: palette.textMuted),
        labelStyle: TextStyle(color: palette.textMuted),
        helperStyle: mutedBodySmall,
        helperMaxLines: 3,
        errorStyle: bodySmall.copyWith(color: palette.danger),
        errorMaxLines: 3,
        floatingLabelStyle: TextStyle(color: palette.primaryStrong),
        prefixStyle: TextStyle(color: palette.textMuted),
        prefixIconColor: palette.textMuted,
        suffixIconColor: palette.textMuted,
        // Flutter keeps a field that is not dense at least 48 tall, so the
        // field clears the 44dp tap target whatever this padding is.
        contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm, vertical: 10),
        border: fieldBorder(palette.stroke, 0.5),
        enabledBorder: fieldBorder(palette.stroke, 0.5),
        focusedBorder: fieldBorder(palette.strokeStrong, 1),
        disabledBorder: fieldBorder(palette.stroke, 0.5),
        errorBorder: fieldBorder(palette.danger, 1),
        focusedErrorBorder: fieldBorder(palette.danger, 1),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          shape: rounded(VeilRadius.md),
          backgroundColor: palette.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: palette.textSubtle,
          textStyle: labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          side: BorderSide(color: palette.stroke),
          foregroundColor: palette.text,
          disabledForegroundColor: palette.textSubtle,
          backgroundColor: Colors.transparent,
          shape: rounded(VeilRadius.md),
          textStyle: labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primaryStrong,
          disabledForegroundColor: palette.textSubtle,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.sm),
          shape: rounded(VeilRadius.md),
          textStyle: labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textMuted,
          disabledForegroundColor: palette.textSubtle,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(44, 44),
        ),
      ),
      // Rows: 16 at the sides; the 6 above and below the text is the
      // tile's own minimum, so a one-line row is 44 and not 44 + 12.
      listTileTheme: ListTileThemeData(
        dense: false,
        minVerticalPadding: 6,
        minLeadingWidth: 0,
        horizontalTitleGap: VeilSpace.sm,
        contentPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
        shape: const RoundedRectangleBorder(),
        tileColor: Colors.transparent,
        iconColor: palette.textMuted,
        textColor: palette.text,
        titleTextStyle: titleMedium,
        subtitleTextStyle: mutedBodyMedium,
        leadingAndTrailingTextStyle: mutedBodyMedium,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.primarySoft,
        disabledColor: palette.surfaceAlt,
        side: BorderSide.none,
        shape: rounded(VeilRadius.xs),
        labelStyle: labelMedium.copyWith(color: palette.text),
        secondaryLabelStyle: labelMedium.copyWith(color: palette.primaryStrong),
        checkmarkColor: palette.primaryStrong,
        iconTheme: IconThemeData(color: palette.textMuted, size: VeilIconSize.sm),
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xs, vertical: VeilSpace.xs),
        labelPadding: const EdgeInsets.symmetric(horizontal: VeilSpace.xxs),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(rounded(VeilRadius.sm)),
          side: WidgetStatePropertyAll(BorderSide(color: palette.stroke, width: 0.5)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? palette.primarySoft : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? palette.primaryStrong : palette.text,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? palette.primaryStrong : palette.textMuted,
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          textStyle: WidgetStatePropertyAll(labelMedium),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: VeilSpace.sm)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.stroke, thickness: 0.5, space: 0.5),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.primary : palette.surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : palette.stroke,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(0.5),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.primary : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: palette.textMuted, width: 1.5),
        shape: rounded(4),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? palette.primary : palette.textMuted,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shadowColor: light ? const Color(0x2E000000) : Colors.transparent,
        elevation: light ? 8 : 0,
        shape: rounded(VeilRadius.lg),
        titleTextStyle: titleLarge,
        contentTextStyle: mutedBodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        modalBackgroundColor: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalElevation: light ? 8 : 0,
        elevation: 0,
        shadowColor: light ? const Color(0x2E000000) : Colors.transparent,
        dragHandleColor: palette.strokeStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(VeilRadius.lg)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: light ? 8 : 0,
        shadowColor: light ? const Color(0x2E000000) : Colors.transparent,
        shape: rounded(VeilRadius.md),
        textStyle: bodyMedium,
        iconColor: palette.textMuted,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: WidgetStatePropertyAll(light ? 8 : 0),
          shape: WidgetStatePropertyAll(rounded(VeilRadius.md)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? palette.primaryStrong : palette.textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => labelSmall.copyWith(
            color: states.contains(WidgetState.selected) ? palette.primaryStrong : palette.textMuted,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primaryStrong,
        linearTrackColor: palette.surfaceAlt,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: palette.primary,
        textColor: Colors.white,
        textStyle: labelSmall.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(VeilRadius.sm),
          border: Border.all(color: palette.stroke, width: 0.5),
        ),
        textStyle: bodySmall,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.primary.withValues(alpha: 0.3),
        selectionHandleColor: palette.primary,
      ),
    );
  }
}

/// The switch theme `Switch.adaptive` uses. On iOS Flutter drops the
/// Material switch theme and draws the Cupertino switch in system green;
/// this keeps the iOS shape and thumb and puts the brand on the track when
/// it is on, as on Android. Elsewhere the theme is used as it is.
class _VeilSwitchAdaptation extends Adaptation<SwitchThemeData> {
  const _VeilSwitchAdaptation(this.palette);

  final VeilPalette palette;

  @override
  SwitchThemeData adapt(ThemeData theme, SwitchThemeData defaultValue) => switch (theme.platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => SwitchThemeData(
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected) ? palette.primary : null,
            ),
          ),
        _ => defaultValue,
      };
}

/// The one type style a screen still names outside the text theme.
@Deprecated('W1 migrates; deleted in W0-TOKENS phase 2. Use Theme.of(context).textTheme.titleLarge.')
class VeilTypography {
  const VeilTypography._();

  /// The bar title: the same metrics as the theme's titleLarge.
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
}

/// Discipline for haptics. Flutter's [HapticFeedback] exposes raw primitives,
/// but good iOS apps use them sparingly and semantically. Prefer these named
/// helpers at call sites so intent is clear and future tuning is centralized.
class VeilHaptics {
  const VeilHaptics._();

  /// Picker-wheel style feedback. Use for selection-in-a-set interactions
  /// (switching tabs, cycling a segmented control, picking from a list).
  static void selection() => HapticFeedback.selectionClick();

  /// Light tap. Default for ordinary button presses that commit nothing
  /// dangerous: "send message", "tap a chip", "confirm a non-destructive
  /// action".
  static void light() => HapticFeedback.lightImpact();

  /// Medium tap. Use for destructive confirmations or meaningful state
  /// transitions (archive, leave room, revoke session).
  static void medium() => HapticFeedback.mediumImpact();

  /// Heavy tap. Reserve for irreversible actions at the tail end of a
  /// confirmation flow (final delete, wipe device).
  static void heavy() => HapticFeedback.heavyImpact();

  /// Quick double-pulse matching iOS UINotificationFeedbackGenerator.success.
  static void success() {
    HapticFeedback.lightImpact();
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      HapticFeedback.lightImpact();
    });
  }

  /// Three-tap warning pattern matching UINotificationFeedbackGenerator.error.
  static void error() {
    HapticFeedback.heavyImpact();
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      HapticFeedback.mediumImpact();
    });
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      HapticFeedback.heavyImpact();
    });
  }
}
