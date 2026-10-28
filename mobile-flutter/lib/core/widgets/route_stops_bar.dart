import 'package:flutter/material.dart';

import '../theme/axis_spacing.dart';
import '../theme/axis_tokens.dart';

/// État d'un arrêt dans la frise de trajet.
enum RouteStopState {
  /// Arrêt passé.
  passed,

  /// Arrêt en cours / étape active.
  current,

  /// Arrêt futur.
  upcoming,
}

/// Modèle d'affichage pour un arrêt dans [RouteStopsBar].
class RouteStopItem {
  const RouteStopItem({
    required this.name,
    this.state = RouteStopState.upcoming,
  });

  final String name;
  final RouteStopState state;
}

/// Frise horizontale représentant les arrêts d'un trajet.
///
/// Utilisée dans les cartes de résultats client et l'en-tête contrôleur.
/// S'adapte au contexte clair ([isDark] = false) ou sombre ([isDark] = true).
class RouteStopsBar extends StatelessWidget {
  const RouteStopsBar({
    super.key,
    required this.stops,
    this.isDark = false,
  });

  final List<RouteStopItem> stops;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();

    final tokens = context.axis;
    final theme = Theme.of(context);

    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.20)
        : tokens.borderStrong;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            // Ligne continue en arrière-plan
            Positioned(
              top: 6,
              left: 7,
              right: 7,
              child: Container(
                height: 2,
                color: trackColor,
              ),
            ),
            // Les arrêts (pastilles + labels)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(stops.length, (index) {
                final stop = stops[index];
                final isFirst = index == 0;
                final isLast = index == stops.length - 1;
                final isEndpoint = isFirst || isLast;

                CrossAxisAlignment alignment = CrossAxisAlignment.center;
                TextAlign textAlign = TextAlign.center;
                if (isFirst) {
                  alignment = CrossAxisAlignment.start;
                  textAlign = TextAlign.start;
                } else if (isLast) {
                  alignment = CrossAxisAlignment.end;
                  textAlign = TextAlign.end;
                }

                // Décoration de la pastille (14 × 14)
                Widget dotWidget;
                if (isDark) {
                  switch (stop.state) {
                    case RouteStopState.passed:
                      dotWidget = Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      );
                    case RouteStopState.current:
                      dotWidget = Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.35),
                              blurRadius: 0,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      );
                    case RouteStopState.upcoming:
                      dotWidget = Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: tokens.ink,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                      );
                  }
                } else {
                  // Contexte clair (ex. carte trajet client)
                  if (stop.state == RouteStopState.current) {
                    dotWidget = Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: tokens.accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tokens.accent.withValues(alpha: 0.35),
                            blurRadius: 0,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    );
                  } else if (isEndpoint || stop.state == RouteStopState.passed) {
                    dotWidget = Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    );
                  } else {
                    dotWidget = Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tokens.iconMuted,
                          width: 2,
                        ),
                      ),
                    );
                  }
                }

                // Style du libellé
                TextStyle? labelStyle;
                if (isDark) {
                  labelStyle = theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: stop.state == RouteStopState.current
                        ? FontWeight.w800
                        : (stop.state == RouteStopState.passed
                            ? FontWeight.w700
                            : FontWeight.w600),
                    color: stop.state == RouteStopState.current
                        ? tokens.accent
                        : (stop.state == RouteStopState.passed
                            ? Colors.white
                            : tokens.iconMuted),
                  );
                } else {
                  final isBold = isEndpoint || stop.state == RouteStopState.current;
                  labelStyle = theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                    color: isBold ? tokens.ink : tokens.textSecondary,
                  );
                }

                return Expanded(
                  child: Column(
                    crossAxisAlignment: alignment,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      dotWidget,
                      const SizedBox(height: AxisSpacing.xs),
                      Text(
                        stop.name,
                        style: labelStyle,
                        textAlign: textAlign,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}

