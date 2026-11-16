// Écran des résultats : pendant le chargement, les villes pas encore connues ne s'affichent pas « À renseigner ».
import 'dart:async';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:axis_transport_flutter/features/trips/presentation/trip_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Store extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}
}

class _SlowApi extends ApiClient {
  _SlowApi(this.places) : super(store: _Store());
  final Completer<List<Place>> places;

  @override
  Future<List<Place>> locations() => places.future;

  @override
  Future<({List<Trip> trips, NextAvailable? nextAvailable})> searchTripsDetailed(TripSearch search) async =>
      (trips: const <Trip>[], nextAvailable: null);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('titre pendant le chargement : jamais « À renseigner », puis les vraies villes', (tester) async {
    final places = Completer<List<Place>>();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_SlowApi(places))],
      child: MaterialApp(
        theme: AxisTheme.light(),
        home: TripResultsScreen(search: TripSearch(originId: 1, destinationId: 3, date: DateTime(2026, 11, 19))),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('À renseigner'), findsNothing);
    expect(find.text('… → …'), findsOneWidget);

    places.complete(const [
      Place(id: 1, name: 'Parakou', address: ''),
      Place(id: 3, name: 'Savè', address: ''),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Parakou → Savè'), findsOneWidget);
    expect(find.textContaining('À renseigner'), findsNothing);
  });
}
