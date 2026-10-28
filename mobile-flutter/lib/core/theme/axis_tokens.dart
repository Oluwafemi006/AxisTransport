import 'package:flutter/material.dart';

import 'axis_colors.dart';

/// Tokens Axis que Material ne couvre pas. Lecture dans un écran : `context.axis.accent`.
@immutable
class AxisTokens extends ThemeExtension<AxisTokens> {
  const AxisTokens({
    required this.accent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.primarySoft,
    required this.primaryDark,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningText,
    required this.danger,
    required this.disabled,
    required this.inputFill,
    required this.border,
    required this.borderStrong,
    required this.iconMuted,
    required this.ink,
    required this.textMuted,
    required this.textSecondary,
    required this.floatingShadow,
  });

  static const light = AxisTokens(
    accent: AxisPalette.accent,
    accentSoft: AxisPalette.accentSoft,
    onAccentSoft: AxisPalette.onAccentSoft,
    primarySoft: AxisPalette.primarySoft,
    primaryDark: AxisPalette.primaryDark,
    success: AxisPalette.success,
    successSoft: AxisPalette.successSoft,
    warning: AxisPalette.warning,
    warningText: AxisPalette.warningText,
    danger: AxisPalette.danger,
    disabled: AxisPalette.disabled,
    inputFill: AxisPalette.inputFill,
    border: AxisPalette.border,
    borderStrong: AxisPalette.borderStrong,
    iconMuted: AxisPalette.iconMuted,
    ink: AxisPalette.ink,
    textMuted: AxisPalette.textMuted,
    textSecondary: AxisPalette.textSecondary,
    // Spec : 0 12 32 rgba(11,60,116,0.14).
    floatingShadow: [
      BoxShadow(
        color: AxisPalette.floatingShadow,
        offset: Offset(0, 12),
        blurRadius: 32,
      ),
    ],
  );

  final Color accent;
  final Color accentSoft;
  final Color onAccentSoft;
  final Color primarySoft;
  final Color primaryDark;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningText;
  final Color danger;
  final Color disabled;
  final Color inputFill;
  final Color border;
  final Color borderStrong;
  final Color iconMuted;
  final Color ink;
  final Color textMuted;
  final Color textSecondary;
  final List<BoxShadow> floatingShadow;

  /// Alias sémantique vers [inputFill] (#F8FAFC) pour les surfaces douces / fonds de cartes secondaires.
  Color get surfaceSoft => inputFill;

  @override
  AxisTokens copyWith({
    Color? accent,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? primarySoft,
    Color? primaryDark,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningText,
    Color? danger,
    Color? disabled,
    Color? inputFill,
    Color? border,
    Color? borderStrong,
    Color? iconMuted,
    Color? ink,
    Color? textMuted,
    Color? textSecondary,
    List<BoxShadow>? floatingShadow,
  }) {
    return AxisTokens(
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccentSoft: onAccentSoft ?? this.onAccentSoft,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryDark: primaryDark ?? this.primaryDark,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningText: warningText ?? this.warningText,
      danger: danger ?? this.danger,
      disabled: disabled ?? this.disabled,
      inputFill: inputFill ?? this.inputFill,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      iconMuted: iconMuted ?? this.iconMuted,
      ink: ink ?? this.ink,
      textMuted: textMuted ?? this.textMuted,
      textSecondary: textSecondary ?? this.textSecondary,
      floatingShadow: floatingShadow ?? this.floatingShadow,
    );
  }

  @override
  AxisTokens lerp(ThemeExtension<AxisTokens>? other, double t) {
    if (other is! AxisTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AxisTokens(
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccentSoft: c(onAccentSoft, other.onAccentSoft),
      primarySoft: c(primarySoft, other.primarySoft),
      primaryDark: c(primaryDark, other.primaryDark),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningText: c(warningText, other.warningText),
      danger: c(danger, other.danger),
      disabled: c(disabled, other.disabled),
      inputFill: c(inputFill, other.inputFill),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      iconMuted: c(iconMuted, other.iconMuted),
      ink: c(ink, other.ink),
      textMuted: c(textMuted, other.textMuted),
      textSecondary: c(textSecondary, other.textSecondary),
      floatingShadow:
          BoxShadow.lerpList(floatingShadow, other.floatingShadow, t) ?? floatingShadow,
    );
  }
}

/// Raccourci : `context.axis.accent`.
extension AxisTokensContext on BuildContext {
  AxisTokens get axis => Theme.of(this).extension<AxisTokens>() ?? AxisTokens.light;
}

