import 'package:flutter/material.dart';

import 'axis_colors.dart';

/// Typographie Axis : Plus Jakarta Sans embarquée (assets/fonts/, fonctionne hors ligne),
/// graisses 500, 600, 700 et 800.
abstract final class AxisTypography {
  static const fontFamily = 'PlusJakartaSans';

  static const _base = TextStyle(
    fontFamily: fontFamily,
    color: AxisPalette.ink,
    letterSpacing: 0,
  );

  /// Prix (20–24 / 800). Hors TextTheme Material : exposé ici pour les composants.
  static final price = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2);

  /// TextTheme Material 3 complet, aligné sur le tableau « Typographie » de la spec.
  static TextTheme textTheme() {
    TextStyle s(double size, FontWeight weight, {double height = 1.3, Color? color}) =>
        _base.copyWith(fontSize: size, fontWeight: weight, height: height, color: color);

    return TextTheme(
      // Chiffre clé (heure de départ) : 30 / 800.
      displayLarge: s(36, FontWeight.w800, height: 1.15),
      displayMedium: s(32, FontWeight.w800, height: 1.15),
      displaySmall: s(30, FontWeight.w800, height: 1.15),
      // Titre d'écran principal (en-tête) : 24–28 / 800.
      headlineLarge: s(28, FontWeight.w800, height: 1.2),
      headlineMedium: s(26, FontWeight.w800, height: 1.2),
      headlineSmall: s(24, FontWeight.w800, height: 1.2),
      // Titre de barre d'écran : 17–19 / 800.
      titleLarge: s(18, FontWeight.w800, height: 1.25),
      // Titre de section / carte : 14–17 / 800.
      titleMedium: s(16, FontWeight.w800, height: 1.3),
      titleSmall: s(14, FontWeight.w800, height: 1.3),
      // Corps : 14–15 / 600–700.
      bodyLarge: s(15, FontWeight.w600, height: 1.45),
      bodyMedium: s(14, FontWeight.w600, height: 1.45),
      // Méta / aide : 11–12 / 500–600.
      bodySmall: s(12, FontWeight.w500, height: 1.4, color: AxisPalette.textMuted),
      // Libellés (boutons, champs) : 12–13 / 600–700 ; boutons à 15 / 800.
      labelLarge: s(15, FontWeight.w800, height: 1.2),
      labelMedium: s(13, FontWeight.w700, height: 1.3),
      labelSmall: s(11, FontWeight.w600, height: 1.3, color: AxisPalette.textMuted),
    );
  }
}

