import 'package:flutter/material.dart';

import '../../core/theme/axis_spacing.dart';
import '../../core/theme/axis_tokens.dart';
import '../../core/widgets/axis_logo.dart';

/// En-tête bleu commun à la connexion et à l'inscription. Il reste fixe en haut de l'écran :
/// seul le formulaire défile en dessous. La marge de la barre d'état est ajoutée (affichage bord à bord).
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;

  /// Bouton retour, affiché seulement s'il est fourni (inscription).
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.axis;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AxisSpacing.screenAuth,
        MediaQuery.paddingOf(context).top + AxisSpacing.lg,
        AxisSpacing.screenAuth,
        AxisSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AxisRadius.authHeader),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                Tooltip(
                  message: 'Retour',
                  child: Semantics(
                    label: 'Retour',
                    button: true,
                    child: Material(
                      color: tokens.onDark.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AxisRadius.small),
                      child: InkWell(
                        onTap: onBack,
                        borderRadius: BorderRadius.circular(AxisRadius.small),
                        child: SizedBox(
                          width: AxisSizes.minTarget,
                          height: AxisSizes.minTarget,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 22,
                            color: tokens.onDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AxisSpacing.sm),
              ],
              const Flexible(child: AxisLogo()),
            ],
          ),
          const SizedBox(height: AxisSpacing.md),
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: tokens.onDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: tokens.borderStrong,
            ),
          ),
        ],
      ),
    );
  }
}
