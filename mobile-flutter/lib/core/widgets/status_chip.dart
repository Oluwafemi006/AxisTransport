import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Variantes sémantiques de [StatusChip].
enum StatusChipVariant {
  success,
  info,
  warning,
  danger,
  neutral,
}

/// Chip de statut réutilisable selon le design system AXIS.
///
/// Affiche un badge coloré compact (fond adouci + texte contrasté)
/// avec une icône optionnelle à gauche.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.variant = StatusChipVariant.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final StatusChipVariant variant;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    final (Color bg, Color fg, Color border) = switch (variant) {
      StatusChipVariant.success => (
          tokens.successSoft,
          tokens.success,
          tokens.success.withValues(alpha: 0.25),
        ),
      StatusChipVariant.info => (
          tokens.primarySoft,
          theme.colorScheme.primary,
          theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      StatusChipVariant.warning => (
          tokens.accentSoft,
          tokens.onAccentSoft,
          tokens.accent.withValues(alpha: 0.35),
        ),
      StatusChipVariant.danger => (
          tokens.danger.withValues(alpha: 0.12),
          tokens.danger,
          tokens.danger.withValues(alpha: 0.25),
        ),
      StatusChipVariant.neutral => (
          tokens.inputFill,
          tokens.textSecondary,
          tokens.border,
        ),
    };

    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: fg,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AxisSpacing.xs : AxisSpacing.sm,
        vertical: dense ? 2 : AxisSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AxisRadius.pill),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: dense ? 12 : 14,
              color: fg,
            ),
            SizedBox(width: dense ? 2 : AxisSpacing.xxs),
          ],
          Text(
            label,
            style: textStyle,
          ),
        ],
      ),
    );
  }
}

