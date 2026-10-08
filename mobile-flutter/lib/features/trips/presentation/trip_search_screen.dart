import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../domain/trip_search.dart';
import 'trip_search_card.dart';

class TripSearchScreen extends StatelessWidget {
  const TripSearchScreen({super.key, this.initialSearch});

  final TripSearch? initialSearch;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rechercher un trajet')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text(
          'Où souhaitez-vous aller ?',
          style: TextStyle(
            color: AxisColors.navyDark,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choisissez votre trajet et consultez les places disponibles.',
          style: TextStyle(color: AxisColors.muted),
        ),
        const SizedBox(height: 22),
        TripSearchCard(initialSearch: initialSearch),
      ],
    ),
  );
}
