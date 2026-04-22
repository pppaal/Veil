import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VeilSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double hero = 56;
}

class VeilRadius {
  static const double xs = 10;
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 30;
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
  // Shorter durations match iOS's snappier feel. Existing call sites read these
  // constants by name, so we keep names stable and only tune the values.
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve emphasize = Cubic(0.2, 0.8, 0.2, 1.0);
  static const Curve smooth = Cubic(0.4, 0.0, 0.2, 1.0);

  // iOS-inspired spring curves approximated as cubic Beziers. Use these for
  // element transitions; page-level transitions already use Cupertino.
  static const Curve springGentle = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve springResponsive = Cubic(0.4, 1.3, 0.45, 1.0);
  static const Curve springBouncy = Cubic(0.16, 1.5, 0.3, 1.0);
}

class VeilElevation {
  // iOS leans on vibrancy and hairlines instead of Material drop shadows. These
  // shadows are deliberately softer than a typical Material elevation set.
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 32,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> chip = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 10,
      offset: Offset(0, 3),
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
    required this.surfaceOverlay,
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
    this.accent = const Color(0xFF8B5CF6),
    this.accentSoft = const Color(0x1A8B5CF6),
  });

  final Color canvas;
  final Color canvasAlt;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceRaised;
  final Color surfaceOverlay;
  final Color stroke;
  final Color strokeStrong;
  final Color primary;
  final Color primaryStrong;
  final Color primarySoft;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color accent;
  final Color accentSoft;

  LinearGradient get primaryGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
      );

  LinearGradient get surfaceGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1C1C21), Color(0xFF111114)],
      );

  static const dark = VeilPalette(
    // Canvas stack follows iOS dark mode tiers: near-black base, quietly
    // lifted surfaces, minimal hue shift so content feels grounded.
    canvas: Color(0xFF000000),
    canvasAlt: Color(0xFF0A0A0C),
    surface: Color(0xFF111114),
    surfaceAlt: Color(0xFF17171B),
    surfaceRaised: Color(0xFF1C1C21),
    surfaceOverlay: Color(0xFF24242B),
    // Hairline tier maps to iOS systemGray separators in dark mode.
    stroke: Color(0xFF2A2A30),
    strokeStrong: Color(0xFF3A3A42),
    // Accent pulled toward iOS system blue (#0A84FF) for a more Apple feel,
    // keeping a slightly richer tertiary for highlighted states.
    primary: Color(0xFF0A84FF),
    primaryStrong: Color(0xFF4FA6FF),
    primarySoft: Color(0x1F0A84FF),
    // Label tiers align with iOS primary/secondary/tertiary label contrast.
    text: Color(0xFFF2F2F7),
    textMuted: Color(0xFF9A9AA1),
    textSubtle: Color(0xFF6A6A71),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    accent: Color(0xFFBF5AF2),
    accentSoft: Color(0x1FBF5AF2),
  );

  // iOS light mode. Background tiers mirror systemBackground /
  // secondarySystemBackground / tertiarySystemBackground. Colors use the
  // documented iOS light system color values so Dynamic Type and system
  // contrast assumptions hold.
  static const light = VeilPalette(
    canvas: Color(0xFFFFFFFF),
    canvasAlt: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2F2F7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceOverlay: Color(0xFFE5E5EA),
    stroke: Color(0xFFD1D1D6),
    strokeStrong: Color(0xFFC6C6C8),
    primary: Color(0xFF007AFF),
    primaryStrong: Color(0xFF0A84FF),
    primarySoft: Color(0x1F007AFF),
    text: Color(0xFF000000),
    textMuted: Color(0xFF3C3C43),
    textSubtle: Color(0x993C3C43),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    danger: Color(0xFFFF3B30),
    accent: Color(0xFFAF52DE),
    accentSoft: Color(0x1FAF52DE),
  );

  /// Resolve the palette matching a [Brightness]. Screens should prefer
  /// `context.veilPalette` which reads the brightness from [Theme.of].
  static VeilPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}

class VeilTheme {
  static ThemeData dark() => _build(VeilPalette.dark, Brightness.dark);

  static ThemeData light() => _build(VeilPalette.light, Brightness.light);

  static ThemeData _build(VeilPalette palette, Brightness brightness) {
    final onPrimary =
        brightness == Brightness.light ? Colors.white : palette.canvas;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.primary,
      onPrimary: onPrimary,
      secondary: palette.primary,
      onSecondary: onPrimary,
      error: palette.danger,
      onError: onPrimary,
      surface: palette.surface,
      onSurface: palette.text,
      outline: palette.stroke,
      outlineVariant: palette.strokeStrong,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.text,
      onInverseSurface: palette.canvas,
      inversePrimary: palette.surfaceRaised,
      surfaceContainerHighest: palette.surfaceRaised,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      dividerColor: palette.stroke,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 42,
          height: 1.02,
          fontWeight: FontWeight.w600,
          letterSpacing: -2.1,
        ),
        headlineLarge: TextStyle(
          fontSize: 30,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.1,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          height: 1.12,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          height: 1.15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.45,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.25,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.15,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          height: 1.24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.05,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.55,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.52,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ).apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        backgroundColor: Colors.transparent,
      ).copyWith(
        foregroundColor: palette.text,
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ).copyWith(color: palette.text),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.lg),
          side: BorderSide(color: palette.stroke),
        ),
        shadowColor: Colors.black,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceRaised,
        contentTextStyle: TextStyle(
          color: palette.text,
          fontSize: 14,
          height: 1.45,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: palette.textSubtle),
        labelStyle: TextStyle(color: palette.textMuted),
        helperStyle: TextStyle(color: palette.textSubtle),
        errorStyle: TextStyle(color: palette.danger),
        floatingLabelStyle: TextStyle(color: palette.primaryStrong),
        prefixIconColor: palette.textMuted,
        suffixIconColor: palette.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: VeilSpace.lg,
          vertical: VeilSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: palette.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: palette.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: palette.strokeStrong, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
          borderSide: BorderSide(color: palette.danger, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xl, vertical: VeilSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.md),
          ),
          backgroundColor: palette.primary,
          foregroundColor: palette.canvas,
          disabledBackgroundColor: palette.surfaceOverlay,
          disabledForegroundColor: palette.textSubtle,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xl, vertical: VeilSpace.md),
          side: BorderSide(color: palette.stroke),
          foregroundColor: palette.text,
          backgroundColor: palette.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.md),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.primary,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.sm),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: false,
        minLeadingWidth: 18,
        minVerticalPadding: VeilSpace.xs,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: VeilSpace.lg,
          vertical: VeilSpace.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.md),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.primarySoft,
        disabledColor: palette.surface,
        side: BorderSide(color: palette.stroke),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.pill),
        ),
        labelStyle: TextStyle(
          color: palette.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: palette.canvas,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: VeilSpace.sm,
          vertical: VeilSpace.xs,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.stroke,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.canvas;
          }
          return palette.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.primary;
          }
          return palette.surfaceRaised;
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VeilRadius.lg),
          side: BorderSide(color: palette.stroke),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceRaised,
        modalBackgroundColor: palette.surfaceRaised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(VeilRadius.lg)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.primary,
        linearTrackColor: palette.surfaceAlt,
      ),
      iconTheme: IconThemeData(
        color: palette.textMuted,
        size: VeilIconSize.md,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textMuted,
          backgroundColor: palette.surfaceAlt.withValues(alpha: 0.4),
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.md),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(VeilRadius.sm),
          border: Border.all(color: palette.stroke),
        ),
        textStyle: TextStyle(
          color: palette.text,
          fontSize: 12,
          height: 1.35,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.primary.withValues(alpha: 0.35),
        selectionHandleColor: palette.primary,
      ),
    );
  }
}

/// iOS Human Interface Guidelines type scale exposed as Flutter TextStyles.
/// Use these when a screen wants to speak the SF Pro vocabulary explicitly
/// (e.g. large title, headline, footnote). Existing screens can keep using
/// [Theme.of(context).textTheme] — this is additive, not a replacement.
class VeilTypography {
  const VeilTypography._();

  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    height: 1.03,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
  );

  static const TextStyle title1 = TextStyle(
    fontSize: 28,
    height: 1.08,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
  );

  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    height: 1.14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
  );

  static const TextStyle title3 = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 1.29,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
  );

  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 1.29,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
  );

  static const TextStyle callout = TextStyle(
    fontSize: 16,
    height: 1.31,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.32,
  );

  static const TextStyle subheadline = TextStyle(
    fontSize: 15,
    height: 1.33,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
  );

  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    height: 1.38,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
  );

  static const TextStyle caption1 = TextStyle(
    fontSize: 12,
    height: 1.33,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
  );

  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    height: 1.27,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.07,
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
  /// dangerous — "send message", "tap a chip", "confirm a non-destructive
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

/// Translucent surface matching iOS nav bars / tab bars. Wrap a child that
/// should sit over scrolling content with a frosted-glass effect. The tint
/// defaults to the palette canvas so the surface darkens content behind it
/// without fully hiding it.
class VeilBlur extends StatelessWidget {
  const VeilBlur({
    super.key,
    required this.child,
    this.intensity = 24,
    this.tint,
    this.tintAlpha = 0.72,
    this.borderRadius,
  });

  /// Child rendered on top of the blurred backdrop.
  final Widget child;

  /// Gaussian blur sigma in logical pixels. iOS navigation bars use ~20.
  final double intensity;

  /// Optional tint laid over the blur. Defaults to the theme canvas.
  final Color? tint;

  /// Opacity of the tint overlay. Lower = more transparent.
  final double tintAlpha;

  /// Optional clip radius for the frosted region.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = VeilPalette.dark;
    final overlay = (tint ?? palette.canvas).withValues(alpha: tintAlpha);
    final filtered = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: intensity, sigmaY: intensity),
      child: Container(color: overlay, child: child),
    );
    if (borderRadius == null) {
      return filtered;
    }
    return ClipRRect(borderRadius: borderRadius!, child: filtered);
  }
}
