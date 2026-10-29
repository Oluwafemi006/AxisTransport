import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// État d'avancement d'une étape dans [TimelineSteps].
enum TimelineStepState {
  /// Étape terminée.
  done,

  /// Étape active / en cours.
  now,

  /// Étape future / à venir.
  todo,
}

/// Modèle pour une étape dans [TimelineSteps].
class TimelineStepItem {
  const TimelineStepItem({
    required this.title,
    this.meta,
    this.state = TimelineStepState.todo,
    this.trailing,
  });

  final String title;
  final String? meta;
  final TimelineStepState state;
  final Widget? trailing;
}

/// Frise verticale d'étapes (suivi de colis, progression de commande, etc.).
class TimelineSteps extends StatelessWidget {
  const TimelineSteps({
    super.key,
    required this.steps,
  });

  final List<TimelineStepItem> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    final tokens = context.axis;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isLast = index == steps.length - 1;

        // Configuration de la pastille (16x16)
        Widget dot;
        switch (step.state) {
          case TimelineStepState.done:
            dot = Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            );
          case TimelineStepState.now:
            dot = Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: tokens.accentSoft,
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ],
              ),
            );
          case TimelineStepState.todo:
            dot = Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: tokens.borderStrong,
                  width: 2,
                ),
              ),
            );
        }

        final lineColor = step.state == TimelineStepState.done
            ? theme.colorScheme.primary
            : tokens.border;

        final titleStyle = theme.textTheme.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: step.state == TimelineStepState.todo
              ? FontWeight.w600
              : FontWeight.w800,
          color: step.state == TimelineStepState.todo
              ? tokens.textSecondary
              : tokens.ink,
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colonne indicatrice : pastille + trait vertical
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 2),
                    dot,
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: lineColor,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AxisSpacing.sm),
              // Contenu texte
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLast ? 0 : AxisSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.title, style: titleStyle),
                            if (step.meta != null) ...[
                              const SizedBox(height: AxisSpacing.xxs),
                              Text(
                                step.meta!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (step.trailing != null) step.trailing!,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

