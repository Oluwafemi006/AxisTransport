import 'package:flutter/material.dart';

import 'theme/axis_colors.dart';
import 'theme/axis_theme.dart';

/// Alias de compatibilité vers [AxisPalette] (défini dans `lib/core/theme/`).
class AxisColors {
  const AxisColors._();

  static const navy = AxisPalette.primary;
  static const navyDark = AxisPalette.primaryDark;
  static const blue = AxisPalette.textSecondary;
  static const red = AxisPalette.danger;
  static const background = AxisPalette.background;
  static const surface = AxisPalette.surface;
  static const surfaceLow = AxisPalette.primarySoft;
  static const border = AxisPalette.border;
  static const text = AxisPalette.ink;
  static const muted = AxisPalette.textMuted;
  static const success = AxisPalette.success;
  static const danger = AxisPalette.danger;
  static const warning = AxisPalette.warning;
  static const seatIdle = AxisPalette.primarySoft;
  static const seatTaken = AxisPalette.disabled;
}

ThemeData axisTheme() => AxisTheme.light();
