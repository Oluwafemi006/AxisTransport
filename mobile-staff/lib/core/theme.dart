import 'package:flutter/material.dart';

class AxisColors {
  const AxisColors._();

  static const navy = Color(0xFF0F2552);
  static const navyDark = Color(0xFF001034);
  static const blue = Color(0xFF4A5D8D);
  static const red = Color(0xFFBB0111);
  static const background = Color(0xFFF8F9FF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFEFF4FF);
  static const border = Color(0xFFC5C6D0);
  static const text = Color(0xFF0B1C30);
  static const muted = Color(0xFF44464F);
  static const success = Color(0xFF005236);
  static const danger = Color(0xFFBA1A1A);
  static const warning = Color(0xFF9A6700);
  static const seatIdle = Color(0xFFE9F2FC);
  static const seatTaken = Color(0xFFE2E8F0);
}

ThemeData axisTheme() {
  const radius = 12.0;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AxisColors.navy,
      primary: AxisColors.navy,
      onPrimary: Colors.white,
      surface: AxisColors.surface,
    ),
    scaffoldBackgroundColor: AxisColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AxisColors.background,
      foregroundColor: AxisColors.navyDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: AxisColors.navyDark,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(
        color: AxisColors.muted,
        fontWeight: FontWeight.w700,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AxisColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AxisColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AxisColors.navy, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AxisColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    ),
  );
}
