import 'package:flutter/material.dart';

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
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Curve emphasize = Curves.easeOutCubic;
  static const Curve smooth = Curves.easeInOutCubic;
}

class VeilElevation {
  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x38000000),
      blurRadius: 36,
      offset: Offset(0, 18),
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
        colors: [Color(0xFF6C8CFF), Color(0xFF8B5CF6)],
      );

  LinearGradient get surfaceGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF131A26), Color(0xFF0E1219)],
      );

  static const dark = VeilPalette(
    canvas: Color(0xFF06080D),
    canvasAlt: Color(0xFF0A0E16),
    surface: Color(0xFF0F141E),
    surfaceAlt: Color(0xFF141A26),
    surfaceRaised: Color(0xFF1A2230),
    surfaceOverlay: Color(0xFF1F293A),
    stroke: Color(0xFF232F42),
    strokeStrong: Color(0xFF2E4060),
    primary: Color(0xFF6C8CFF),
    primaryStrong: Color(0xFF93ABFF),
    primarySoft: Color(0x1A6C8CFF),
    text: Color(0xFFF0F4FA),
    textMuted: Color(0xFF8E9BB0),
    textSubtle: Color(0xFF5E6B7F),
    success: Color(0xFF5CE0B0),
    warning: Color(0xFFFFBE6D),
    danger: Color(0xFFFF7B93),
  );
}

class VeilTheme {
  static ThemeData dark() {
    const palette = VeilPalette.dark;
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.primary,
      onPrimary: palette.canvas,
      secondary: palette.primary,
      onSecondary: palette.canvas,
      error: palette.danger,
      onError: palette.canvas,
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
      brightness: Brightness.dark,
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
        selectionColor: Color(0x5588A9C4),
        selectionHandleColor: palette.primary,
      ),
    );
  }
}
