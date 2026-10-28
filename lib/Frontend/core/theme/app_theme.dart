import 'package:flutter/material.dart';

/// Restaurant-themed Material Design 3 theme, shared by every role's UI.
class AppTheme {
  static const Color primary = Color(0xFFB33A2E); // warm terracotta
  static const Color secondary = Color(0xFF2E5339); // deep green accent
  static const Color background = Color(0xFFFAF7F2);

  /// Noto Sans, bundled with the app (see pubspec.yaml, assets/fonts) instead of
  /// the phone's own font. Some phones use a custom system font that has no peso
  /// sign, which showed up as an empty box. Noto Sans has it, so the app looks
  /// the same on every phone.
  static const String fontFamily = 'NotoSans';

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      secondary: secondary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: IconThemeData(color: primary),
      ),
    );
  }
}