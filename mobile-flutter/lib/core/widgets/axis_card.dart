import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// Carte standard Axis Transport.
///
/// Deux variantes :
/// - normale : fond blanc `surface`, bordure `border`, sans élévation.
/// - flottante (`floating: true`) : ombre `floatingShadow` de la spec, sans bordure.
class AxisCard extends StatelessWidget {
  const AxisCard({
    super.key,
    required this.child,
    this.onTap,
    this.floating = false,
    this.padding = const EdgeInsets.all(AxisSpacing.s16),
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool floating;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final axis = context.axis;
    final bg = backgroundColor ?? Theme.of(context).colorScheme.surface;

    final decoration = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AxisRadius.card),
      border: floating ? null : Border.all(color: axis.border),
      boxShadow: floating ? axis.floatingShadow : null,
    );

    Widget content = Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AxisRadius.card),
          child: content,
        ),
      );
    }

    return content;
  }
}

