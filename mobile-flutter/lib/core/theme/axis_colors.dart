import 'package:flutter/painting.dart';

/// Palette Axis : valeurs exactes du tableau « Couleurs » de docs/design/DESIGN_SPEC.md.
///
/// Les écrans ne lisent jamais ces constantes directement : ils passent par
/// `Theme.of(context)` ou `context.axis` (AxisTokens). Seul `lib/core/theme/` les utilise.
///
/// Nom de classe `AxisPalette` (et non `AxisColors`) pour ne pas entrer en conflit avec
/// l'ancienne classe `AxisColors` de `lib/core/theme.dart`, encore utilisée par les écrans
/// jusqu'à leur refonte.
abstract final class AxisPalette {
  static const primary = Color(0xFF0B3C74);
  static const primaryDark = Color(0xFF072A52);
  static const primarySoft = Color(0xFFE8EEF7);
  static const accent = Color(0xFFF5A524);
  static const accentSoft = Color(0xFFFFF4DC);
  static const onAccentSoft = Color(0xFF8A5A00);
  static const ink = Color(0xFF0E1B2C);
  static const textSecondary = Color(0xFF3D4C5F);
  static const textMuted = Color(0xFF5B6B7F);
  static const iconMuted = Color(0xFF8FA3BF);
  static const background = Color(0xFFF4F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const inputFill = Color(0xFFF8FAFC);
  static const border = Color(0xFFE1E7F0);
  static const borderStrong = Color(0xFFC9D6E8);
  static const disabled = Color(0xFFD5DDE8);
  static const success = Color(0xFF1C6B35);
  static const successSoft = Color(0xFFE6F4EA);
  static const warning = Color(0xFFB45309);
  static const warningText = Color(0xFF92400E);
  static const danger = Color(0xFFB91C1C);

  /// Blanc pur pour le texte sur `primary`, `ink`, `success` ou `danger`.
  static const onDark = Color(0xFFFFFFFF);

  /// Couleur de l'ombre des cartes flottantes : rgba(11, 60, 116, 0.14).
  static const floatingShadow = Color(0x240B3C74);
}

