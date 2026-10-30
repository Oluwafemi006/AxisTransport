import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/trips/domain/segment_departure.dart';
import 'package:flutter_test/flutter_test.dart';

Fare _fare(int id, num amount) =>
    Fare(id: id, name: 'TEST $id', amount: amount, currency: 'XOF');

Trip _trip(int id, List<(int, String)> stops, Fare? fare, DateTime departure) => Trip(
  id: id,
  route: RouteInfo(
    id: id,
    label: 'TEST',
    origin: Place(id: stops.first.$1, name: stops.first.$2, address: ''),
    destination: Place(id: stops.last.$1, name: stops.last.$2, address: ''),
    stops: [
      for (var index = 0; index < stops.length; index++)
        RouteStopInfo(id: stops[index].$1, name: stops[index].$2, position: index + 1),
    ],
  ),
  departureAt: departure,
  status: 'SCHEDULED',
  statusDisplay: 'Programmé',
  note: '',
  availableSeats: 5,
  currentFare: fare,
);

/// Faux serveur : grille par tronçon ; sans tarif, repli sur le prix du parcours entier.
class _Api extends ApiClient {
  _Api(this.all, this.grid) : super(store: SessionStore());

  final List<Trip> all;
  final Map<(int, int), Fare> grid;
  final asked = <(int, int)>[];

  @override
  Future<List<Trip>> trips() async => all;

  @override
  Future<List<Trip>> tripsForSegment(int originId, int destinationId) async {
    asked.add((originId, destinationId));
    return [
      for (final trip in all)
        if (_serves(trip, originId, destinationId))
          _trip(
            trip.id,
            [for (final stop in trip.route.stops) (stop.id, stop.name)],
            grid[(originId, destinationId)] ?? trip.currentFare,
            trip.departureAt,
          ),
    ];
  }

  bool _serves(Trip trip, int originId, int destinationId) {
    final ids = trip.route.stops.map((stop) => stop.id).toList();
    final from = ids.indexOf(originId);
    return from >= 0 && ids.indexOf(destinationId) > from;
  }
}

void main() {
  const line = [(2, 'Parakou'), (3, 'Savè'), (1, 'Cotonou')];
  final morning = DateTime(2026, 11, 2, 8);
  final later = DateTime(2026, 11, 3, 8);

  test('une carte par combinaison dans le sens du bus, au tarif du serveur', () async {
    final api = _Api(
      [_trip(10, line, _fare(1, 7500), morning)],
      {(2, 3): _fare(2, 4500), (2, 1): _fare(1, 7500), (3, 1): _fare(3, 6500)},
    );

    final departures = await loadSegmentDepartures(api);

    expect(
      [for (final item in departures) (item.label, item.trip.currentFare!.amount)],
      [
        ('Parakou → Savè', 4500),
        ('Parakou → Cotonou', 7500),
        ('Savè → Cotonou', 6500),
      ],
    );
    expect(api.asked, isNot(contains((3, 2))));
    expect(
      departures.first.bookingLocation,
      '/billets/booking/10/passagers?passagers=1&origin=2&destination=3',
    );
  });

  test('les deux sens sont distincts et chaque tronçon n\'est demandé qu\'une fois', () async {
    final api = _Api(
      [
        _trip(10, line, _fare(1, 7500), morning),
        _trip(11, line, _fare(1, 7500), later),
        _trip(12, line.reversed.toList(), _fare(1, 7500), later),
      ],
      {
        (2, 3): _fare(2, 4500), (3, 2): _fare(2, 4500),
        (2, 1): _fare(1, 7500), (1, 2): _fare(1, 7500),
        (3, 1): _fare(3, 6500), (1, 3): _fare(3, 6500),
      },
    );

    final departures = await loadSegmentDepartures(api);

    expect(api.asked.length, 6);
    expect(api.asked.toSet().length, 6);
    expect(departures.length, 9);
    expect(departures.map((item) => item.label), contains('Cotonou → Savè'));
    expect(departures.first.trip.id, 10);
  });

  test('un tronçon sans tarif est masqué, jamais au prix du parcours entier', () async {
    final api = _Api(
      [_trip(10, line, _fare(1, 7500), morning)],
      {(2, 3): _fare(2, 4500), (2, 1): _fare(1, 7500)},
    );

    final labels = (await loadSegmentDepartures(api)).map((item) => item.label);

    expect(labels, ['Parakou → Savè', 'Parakou → Cotonou']);
  });

  test('un départ sans tarif n\'affiche aucune carte', () async {
    final api = _Api([_trip(10, line, null, morning)], const {});

    expect(await loadSegmentDepartures(api), isEmpty);
  });
}
