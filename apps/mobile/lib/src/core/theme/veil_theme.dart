import 'package:flutter/material.dart';

class VeilTheme {
  static const _bg = Color(0xFF090B0F);
  static const _panel = Color(0xFF11161D);
  static const _panelAlt = Color(0xFF171E27);
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
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: _text),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: _muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panelAlt,
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
      cardTheme: CardThemeData(
        color: _panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: _stroke),
        ),
      ),
      useMaterial3: true,
    );
  }
}
