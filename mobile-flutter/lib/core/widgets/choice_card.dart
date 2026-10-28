import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Variante visuelle pour l'état sélectionné de [ChoiceCard].
enum ChoiceCardTone {
  /// Fond bleu primary avec texte blanc (ex: formule de location).
  primary,

  /// Fond sombre ink avec texte blanc (ex: paiement guichet/contrôleur).
  ink,
}

/// Carte de choix sélectionnable pour listes d'options ou grilles (ex. formules, destinations).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    this.subtitle,
    this.price,
    this.unit,
    this.icon,
    this.badge,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.tone = ChoiceCardTone.primary,
  });

  final String title;
  final String? subtitle;
  final String? price;
  final String? unit;
  final IconData? icon;
  final Widget? badge;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final ChoiceCardTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    final selectedBg = switch (tone) {
      ChoiceCardTone.primary => theme.colorScheme.primary,
      ChoiceCardTone.ink => tokens.ink,
    };

    final bg = !enabled
        ? tokens.surfaceSoft
        : selected
            ? selectedBg
            : theme.colorScheme.surface;

    final borderColor = !enabled
        ? tokens.border
        : selected
            ? selectedBg
            : tokens.border;

    final titleColor = !enabled
        ? tokens.textMuted
        : selected
            ? Colors.white
            : tokens.ink;

    final subtitleColor = !enabled
        ? tokens.textMuted
        : selected
            ? Colors.white.withValues(alpha: 0.85)
            : tokens.textSecondary;

    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AxisRadius.sm),
        side: BorderSide(
          color: borderColor,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AxisRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AxisSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null || icon != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (icon != null)
                      Icon(
                        icon,
                        size: 20,
                        color: titleColor,
                      ),
                    ?badge,
                  ],
                ),
              if (badge != null || icon != null)
                const SizedBox(height: AxisSpacing.xs),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: titleColor,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AxisSpacing.xxs),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (price != null) ...[
                const SizedBox(height: AxisSpacing.xxs),
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(text: price!),
                      if (unit != null)
                        TextSpan(
                          text: ' $unit',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: subtitleColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

