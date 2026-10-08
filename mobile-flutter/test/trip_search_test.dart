import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la recherche produit les filtres attendus par l’API', () async {
    final search = TripSearch(
      originId: 1,
      destinationId: 2,
      date: DateTime(2026, 10, 4),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
    RequestOptions? captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(Response(requestOptions: options, data: <dynamic>[]));
        },
      ),
    );

    final trips = await ApiClient(dio: dio).searchTrips(search);

    expect(trips, isEmpty);
    expect(captured?.path, '/trips/');
    expect(captured?.queryParameters, {
      'origin': '1',
      'destination': '2',
      'date': '2026-10-04',
    });
    expect(
      TripSearch.fromQueryParameters(
        Uri.parse(search.resultsLocation).queryParameters,
      )?.dateKey,
      '2026-10-04',
    );
  });

  test('un lien de recherche invalide ne crée pas de trajet trompeur', () {
    expect(
      TripSearch.fromQueryParameters({
        'origin': '1',
        'destination': '1',
        'date': '2026-10-04',
      }),
      isNull,
    );
    expect(
      TripSearch.fromQueryParameters({
        'origin': '1',
        'destination': '2',
        'date': '2026-99-04',
      }),
      isNull,
    );
  });

  test('les résultats reprennent les horaires et lieux fournis par Django', () {
    final trip = Trip.fromJson({
      'id': 7,
      'route_detail': {
        'id': 3,
        'label': 'Cotonou → Parakou',
        'origin_detail': {'id': 1, 'name': 'Cotonou', 'address': ''},
        'destination_detail': {'id': 2, 'name': 'Parakou', 'address': ''},
      },
      'departure_at': '2026-10-04T08:00:00Z',
      'arrival_at': '2026-10-04T14:00:00Z',
      'vehicle_detail': {'name': 'Bus 04'},
      'status': 'SCHEDULED',
      'available_seats': 12,
      'current_fare': {
        'id': 2,
        'name': 'Standard',
        'amount': '5000.00',
        'currency': 'XOF',
      },
    });

    expect(trip.route.origin?.name, 'Cotonou');
    expect(trip.route.destination?.name, 'Parakou');
    expect(trip.arrivalAt, DateTime.utc(2026, 10, 4, 14).toLocal());
    expect(trip.vehicleName, 'Bus 04');
    expect(trip.currentFare?.amount, 5000);
    expect(Trip.fromJson(trip.toJson()).route.destination?.name, 'Parakou');
  });
}
