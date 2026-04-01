import 'package:flutter/material.dart';

class VeilTheme {
  static const _bg = Color(0xFF090B0F);
  static const _panel = Color(0xFF11161D);
  static const _panelAlt = Color(0xFF171E27);
  static const _panelRaised = Color(0xFF1B2430);
  static const _stroke = Color(0xFF263445);
  static const _accent = Color(0xFF6D96B6);
  static const _muted = Color(0xFF8D9AA8);
  static const _text = Color(0xFFF1F4F8);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: _accent,
      surface: _panel,
      primary: _accent,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(surface: _panel, secondary: _accent, outline: _stroke),
      scaffoldBackgroundColor: _bg,
      cardColor: _panel,
      dividerColor: _stroke,
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 38, fontWeight: FontWeight.w600, letterSpacing: -1.6),
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.9),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: _text),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: _muted),
        labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: _text,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: _text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panelAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(color: _muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: _accent,
          foregroundColor: _bg,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: _stroke),
          foregroundColor: _text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        color: _panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _stroke),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        iconColor: _muted,
      ),
      useMaterial3: true,
    );
  }
}
