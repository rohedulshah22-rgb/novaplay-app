import 'package:flutter/material.dart';

abstract final class NovaColors {
  static const black = Color(0xFF050609);
  static const surface = Color(0xFF0E1016);
  static const surfaceElevated = Color(0xFF151823);
  static const border = Color(0xFF242938);
  static const cyan = Color(0xFF61F2E7);
  static const violet = Color(0xFFA98BFF);
  static const text = Color(0xFFF5F7FB);
  static const muted = Color(0xFF8B93A7);
  static const green = Color(0xFF55E6A5);
  static const yellow = Color(0xFFFFD166);
}

ThemeData buildNovaTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: NovaColors.cyan,
        brightness: Brightness.dark,
        surface: NovaColors.surface,
      ).copyWith(
        primary: NovaColors.cyan,
        secondary: NovaColors.violet,
        surface: NovaColors.surface,
        onSurface: NovaColors.text,
        outline: NovaColors.border,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NovaColors.black,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: NovaColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: NovaColors.surface.withValues(alpha: .94),
      indicatorColor: NovaColors.cyan.withValues(alpha: .13),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: NovaColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? NovaColors.cyan
              : NovaColors.muted,
          size: 22,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NovaColors.surfaceElevated,
      hintStyle: const TextStyle(color: NovaColors.muted),
      prefixIconColor: NovaColors.muted,
      suffixIconColor: NovaColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: NovaColors.cyan, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: NovaColors.surfaceElevated,
      selectedColor: NovaColors.cyan.withValues(alpha: .16),
      labelStyle: const TextStyle(
        color: NovaColors.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide.none,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: NovaColors.cyan,
      inactiveTrackColor: NovaColors.border,
      thumbColor: NovaColors.cyan,
      overlayColor: NovaColors.cyan.withValues(alpha: .12),
      trackHeight: 3,
    ),
  );
}
