import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/axis_theme.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/trip_search.dart';
import 'trip_search_card.dart';

class TripSearchScreen extends StatelessWidget {
  const TripSearchScreen({super.key, this.initialSearch});

  final TripSearch? initialSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = context.axis;

    return Scaffold(
      body: Column(
        children: [
          AxisHeader(
            title: 'Rechercher un trajet',
            subtitle: 'Choisissez votre trajet et consultez les places disponibles.',
            onBack: () => context.canPop() ? context.pop() : context.go('/'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AxisSpacing.screen,
                AxisSpacing.s20,
                AxisSpacing.screen,
                AxisSpacing.s24,
              ),
              children: [
                Text(
                  'Où voyagez-vous aujourd’hui ?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: axis.ink,
                  ),
                ),
                const SizedBox(height: AxisSpacing.s16),
                TripSearchCard(initialSearch: initialSearch),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
