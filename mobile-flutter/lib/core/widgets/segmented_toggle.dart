import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Option générique pour un [SegmentedToggle].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

/// Style visuel de [SegmentedToggle].
enum SegmentedToggleStyle {
  /// Fond blanc/surface avec bordure sélectionnée (ex. formulaire, carte).
  surface,

  /// Fond translucide adapté aux en-têtes colorés (ex. bleu primary de l'en-tête).
  header,
}

/// Sélecteur segmenté accessible à 2 options ou plus.
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.style = SegmentedToggleStyle.surface,
  });

  final List<SegmentOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final SegmentedToggleStyle style;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);

    if (style == SegmentedToggleStyle.header) {
      return Container(
        padding: const EdgeInsets.all(AxisSpacing.xxs),
        decoration: BoxDecoration(
          color: tokens.onDark.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AxisRadius.md),
        ),
        child: Row(
          children: options.map((option) {
            final isSelected = option.value == selectedValue;
            return Expanded(
              child: Semantics(
                button: true,
                selected: isSelected,
                label: option.label,
                child: InkWell(
                  onTap: () => onChanged(option.value),
                  borderRadius: BorderRadius.circular(AxisRadius.sm),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? tokens.onDark : Colors.transparent,
                      borderRadius: BorderRadius.circular(AxisRadius.sm),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (option.icon != null) ...[
                          Icon(
                            option.icon,
                            size: 16,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : tokens.onDark,
                          ),
                          const SizedBox(width: AxisSpacing.xs),
                        ],
                        Text(
                          option.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : tokens.onDark,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // Style standard (surface / formulaire)
    return Row(
      children: options.map((option) {
        final isSelected = option.value == selectedValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AxisSpacing.xxs),
            child: Semantics(
              button: true,
              selected: isSelected,
              label: option.label,
              child: Material(
                color: isSelected ? tokens.ink : theme.colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AxisRadius.sm),
                  side: BorderSide(
                    color: isSelected ? tokens.ink : tokens.border,
                    width: 2,
                  ),
                ),
                child: InkWell(
                  onTap: () => onChanged(option.value),
                  borderRadius: BorderRadius.circular(AxisRadius.sm),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AxisSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (option.icon != null) ...[
                          Icon(
                            option.icon,
                            size: 16,
                            color: isSelected ? tokens.onDark : tokens.ink,
                          ),
                          const SizedBox(width: AxisSpacing.xs),
                        ],
                        Flexible(
                          // Le libellé en gras ne doit pas être tronqué : il réduit plutôt que de perdre sa fin.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              option.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: isSelected ? tokens.onDark : tokens.ink,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

