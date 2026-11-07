import 'package:flutter/material.dart';

import '../theme/axis_colors.dart';
import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

enum AxisButtonVariant {
  /// Fond ambre (`accent`), texte bleu marine (`primary`) ou quasi-noir (`ink`).
  primary,

  /// Fond bleu marine (`primary`), texte blanc.
  secondary,

  /// Fond transparent, bordure `borderStrong`, texte `primary`.
  outline,

  /// Fond transparent sans bordure, texte `primary`.
  ghost,
}

enum AxisButtonTextColor {
  /// Bleu marine Axis (`#0B3C74`), pour le parcours client.
  primary,

  /// Quasi-noir (`#0E1B2C`), pour l'espace contrôleur.
  ink,
}

/// Bouton standard Axis Transport.
///
/// Stylé entièrement par les tokens du thème. Hauteur 54 px par défaut,
/// pleine largeur par défaut, cible tactile minimale garantie.
class AxisButton extends StatelessWidget {
  const AxisButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AxisButtonVariant.primary,
    this.textColor = AxisButtonTextColor.primary,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.height = AxisSizes.primaryButton,
  });

  final String label;
  final VoidCallback? onPressed;
  final AxisButtonVariant variant;
  final AxisButtonTextColor textColor;
  final Widget? icon;
  final bool loading;
  final bool expanded;
  final double height;

  bool get _disabled => onPressed == null || loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    Color bg;
    Color fg;
    BorderSide side = BorderSide.none;

    switch (variant) {
      case AxisButtonVariant.primary:
        bg = axis.accent;
        fg = textColor == AxisButtonTextColor.ink ? axis.ink : theme.colorScheme.primary;
        break;
      case AxisButtonVariant.secondary:
        bg = theme.colorScheme.primary;
        fg = AxisPalette.onDark;
        break;
      case AxisButtonVariant.outline:
        bg = Colors.transparent;
        fg = theme.colorScheme.primary;
        side = BorderSide(color: axis.borderStrong, width: 1.5);
        break;
      case AxisButtonVariant.ghost:
        bg = Colors.transparent;
        fg = theme.colorScheme.primary;
        break;
    }

    if (_disabled) {
      if (variant == AxisButtonVariant.outline || variant == AxisButtonVariant.ghost) {
        bg = Colors.transparent;
        fg = axis.textMuted;
        if (variant == AxisButtonVariant.outline) {
          side = BorderSide(color: axis.border, width: 1);
        }
      } else {
        bg = axis.disabled;
        fg = axis.textMuted;
      }
    }

    Widget content;
    if (loading) {
      content = SizedBox(
        width: AxisSizes.icon,
        height: AxisSizes.icon,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(fg),
        ),
      );
    } else {
      final textWidget = Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelLarge?.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      );
      if (icon != null) {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme(
              data: IconThemeData(color: fg, size: AxisSizes.icon),
              child: icon!,
            ),
            const SizedBox(width: AxisSpacing.s8),
            // Écran étroit ou texte agrandi : le libellé passe à la ligne au lieu de déborder.
            Flexible(child: textWidget),
          ],
        );
      } else {
        content = textWidget;
      }
    }

    Widget button = Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AxisRadius.button),
        side: side,
      ),
      child: InkWell(
        onTap: _disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(AxisRadius.button),
        child: Container(
          height: height.clamp(AxisSizes.minTarget, double.infinity),
          padding: const EdgeInsets.symmetric(horizontal: AxisSpacing.s16),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    if (expanded) {
      button = SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}

