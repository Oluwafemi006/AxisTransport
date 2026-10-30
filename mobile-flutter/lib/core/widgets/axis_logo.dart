import 'package:flutter/material.dart';

import '../theme/axis_colors.dart';
import '../theme/axis_spacing.dart';

/// Logo officiel sur pastille blanche : son texte bleu marine disparaîtrait sur les en-têtes `primary`.
class AxisLogo extends StatelessWidget {
  const AxisLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AxisSizes.minTarget,
      padding: const EdgeInsets.symmetric(
        horizontal: AxisSpacing.s8,
        vertical: AxisSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: AxisPalette.surface,
        borderRadius: BorderRadius.circular(AxisRadius.small),
      ),
      child: Image.asset(
        'assets/axis-logo-transparent.png',
        fit: BoxFit.contain,
        semanticLabel: 'Axis Transport',
      ),
    );
  }
}
