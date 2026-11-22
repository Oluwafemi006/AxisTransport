import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:axis_transport_flutter/features/trips/presentation/trip_results_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Trip _trip() => Trip.fromJson({
      'id': 7,
      'route_detail': {
        'id': 3,
        'label': 'Parakou TEST → Cotonou TEST',
        'origin_detail': {'id': 1, 'name': 'Parakou TEST', 'address': ''},
        'destination_detail': {'id': 4, 'name': 'Cotonou TEST', 'address': ''},
        'stops': [
          {'id': 1, 'name': 'Parakou TEST', 'position': 1},
          {'id': 2, 'name': 'Savè TEST', 'position': 2},
          {'id': 3, 'name': 'Bohicon TEST', 'position': 3},
          {'id': 4, 'name': 'Cotonou TEST', 'position': 4},
        ],
      },
      'departure_at': '2026-11-22T12:00:00Z',
      'status': 'SCHEDULED',
      'available_seats': 12,
    });

void main() {
  test('titre de la carte : le trajet choisi, pas la ligne complète', () {
    final search = TripSearch(originId: 2, destinationId: 3, date: DateTime(2026, 11, 22), passengers: 1);
    expect(segmentTitle(_trip(), search), 'Savè TEST → Bohicon TEST');
  });

  test('sans recherche : la ligne complète', () {
    expect(segmentTitle(_trip(), null), 'Parakou TEST → Cotonou TEST');
  });
}
