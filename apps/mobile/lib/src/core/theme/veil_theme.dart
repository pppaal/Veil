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
}

class VeilRadius {
  static const double sm = 14;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;
}

class VeilIconSize {
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
  static const double xl = 40;
}

class VeilMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
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
    required this.primarySoft,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final Color canvas;
  final Color canvasAlt;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceRaised;
  final Color stroke;
  final Color strokeStrong;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color textMuted;
  final Color textSubtle;
  final Color success;
  final Color warning;
  final Color danger;

  static const dark = VeilPalette(
    canvas: Color(0xFF07090C),
    canvasAlt: Color(0xFF0B1016),
    surface: Color(0xFF10161D),
    surfaceAlt: Color(0xFF151D27),
    surfaceRaised: Color(0xFF1B2430),
    stroke: Color(0xFF263445),
    strokeStrong: Color(0xFF355069),
    primary: Color(0xFF88A9C4),
    primarySoft: Color(0x1F88A9C4),
    text: Color(0xFFF3F6FA),
    textMuted: Color(0xFFA3AFBC),
    textSubtle: Color(0xFF7C8895),
    success: Color(0xFF8BE0C4),
    warning: Color(0xFFFFD28D),
    danger: Color(0xFFFFA8B7),
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
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xl, vertical: VeilSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VeilRadius.md),
          ),
          backgroundColor: palette.primary,
          foregroundColor: palette.canvas,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.xl, vertical: VeilSpace.md),
          side: BorderSide(color: palette.stroke),
          foregroundColor: palette.text,
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
