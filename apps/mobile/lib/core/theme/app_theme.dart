import 'package:flutter/material.dart';

class AppTheme {
  static const primary = Color(0xFF1B5E8B);
  static const accent = Color(0xFFF5A623);
  static const background = Color(0xFFF8F9FA);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Tajawal',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
          centerTitle: false, backgroundColor: background, elevation: 0),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade200)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }
}
