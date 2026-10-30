import '../../../core/api_client.dart';
import '../../../core/models.dart';

/// Un départ vendu sur un tronçon précis ; son tarif vient toujours du serveur.
class SegmentDeparture {
  const SegmentDeparture({
    required this.trip,
    required this.originId,
    required this.destinationId,
    required this.originName,
    required this.destinationName,
    required this.stopOrder,
  });

  final Trip trip;
  final int originId;
  final int destinationId;
  final String originName;
  final String destinationName;

  /// Rang du tronçon dans le sens du bus, pour ranger les cartes d'un même départ.
  final int stopOrder;

  String get label => '$originName → $destinationName';

  String get bookingLocation =>
      '/billets/booking/${trip.id}/passagers?passagers=1'
      '&origin=$originId&destination=$destinationId';
}

/// Arrêts du départ, déjà rangés par le serveur dans le sens du bus.
List<({int id, String name})> _stopsOf(Trip trip) {
  final stops = trip.route.stops;
  if (stops.length >= 2) {
    return [for (final stop in stops) (id: stop.id, name: stop.name)];
  }
  final origin = trip.route.origin;
  final destination = trip.route.destination;
  if (origin == null || destination == null) return const [];
  return [
    (id: origin.id, name: origin.name),
    (id: destination.id, name: destination.name),
  ];
}

/// Sans tarif pour un tronçon, le serveur renvoie celui du parcours entier :
/// ce tronçon n'est pas vendable et ne doit pas afficher ce prix.
bool _hasOwnFare(Trip trip, int originId, int destinationId, Object? fullFareId) {
  final fare = trip.currentFare;
  if (fare == null) return false;
  final isFullRoute =
      trip.route.origin?.id == originId &&
      trip.route.destination?.id == destinationId;
  return isFullRoute || fare.id != fullFareId;
}

/// Toutes les combinaisons d'arrêts de chaque départ. Une requête par tronçon :
/// le serveur ne donne le tarif d'un tronçon que si on le lui demande.
Future<List<SegmentDeparture>> loadSegmentDepartures(ApiClient api) async {
  final trips = await api.trips();
  final fullFareIds = {for (final trip in trips) trip.id: trip.currentFare?.id};
  final segments = <(int, int), ({String origin, String destination, int order})>{};
  for (final trip in trips) {
    final stops = _stopsOf(trip);
    for (var from = 0; from < stops.length - 1; from++) {
      for (var to = from + 1; to < stops.length; to++) {
        segments.putIfAbsent(
          (stops[from].id, stops[to].id),
          () => (
            origin: stops[from].name,
            destination: stops[to].name,
            order: segments.length,
          ),
        );
      }
    }
  }
  final perSegment = await Future.wait(
    segments.entries.map((segment) async {
      final (originId, destinationId) = segment.key;
      final found = await api.tripsForSegment(originId, destinationId);
      return [
        for (final trip in found)
          if (_hasOwnFare(trip, originId, destinationId, fullFareIds[trip.id]))
            SegmentDeparture(
              trip: trip,
              originId: originId,
              destinationId: destinationId,
              originName: segment.value.origin,
              destinationName: segment.value.destination,
              stopOrder: segment.value.order,
            ),
      ];
    }),
  );
  return perSegment.expand((items) => items).toList()..sort((a, b) {
    final byDate = a.trip.departureAt.compareTo(b.trip.departureAt);
    return byDate != 0 ? byDate : a.stopOrder.compareTo(b.stopOrder);
  });
}
