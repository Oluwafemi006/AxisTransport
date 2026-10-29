import 'package:flutter/material.dart';

import '../theme/axis_colors.dart';
import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

enum AxisHeaderVariant {
  /// Espace client : fond bleu marine `primary`.
  client,

  /// Espace contrôleur : fond quasi-noir `ink` avec badge `CONTRÔLEUR` sur `accent`.
  controller,
}

/// En-tête d'écran Axis Transport.
///
/// Deux ambiances visuelles étanches : client (`primary`) et contrôleur (`ink`).
class AxisHeader extends StatelessWidget {
  const AxisHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.variant = AxisHeaderVariant.client,
    this.onBack,
    this.action,
    this.bottom,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final AxisHeaderVariant variant;
  final VoidCallback? onBack;
  final Widget? action;
  final Widget? bottom;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    final isController = variant == AxisHeaderVariant.controller;
    final bg = isController ? axis.ink : theme.colorScheme.primary;

    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          AxisSpacing.screen,
          MediaQuery.paddingOf(context).top + AxisSpacing.s12,
          AxisSpacing.screen,
          AxisSpacing.s16,
        );

    Widget? backButton;
    if (onBack != null) {
      backButton = Tooltip(
        message: 'Retour',
        child: Semantics(
          button: true,
          label: 'Retour',
          child: Material(
            color: const Color(0x1FFFFFFF),
            borderRadius: BorderRadius.circular(AxisRadius.small),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(AxisRadius.small),
              child: const SizedBox(
                width: AxisSizes.minTarget,
                height: AxisSizes.minTarget,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AxisPalette.onDark,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isController) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AxisSpacing.s8,
              vertical: AxisSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: axis.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'CONTRÔLEUR',
              style: theme.textTheme.labelSmall?.copyWith(
                color: axis.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: AxisSpacing.s4),
        ],
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: AxisPalette.onDark,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: AxisSpacing.s4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: axis.borderStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      color: bg,
      padding: effectivePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (backButton != null) ...[
                backButton,
                const SizedBox(width: AxisSpacing.s12),
              ],
              Expanded(child: titleBlock),
              if (action != null) ...[
                const SizedBox(width: AxisSpacing.s12),
                action!,
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: AxisSpacing.s12),
            bottom!,
          ],
        ],
      ),
    );
  }
}

