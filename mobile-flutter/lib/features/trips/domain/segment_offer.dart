import 'package:intl/intl.dart';

import '../../../core/benin_time.dart';
import 'trip_search.dart';

/// Sens de la ligne demandé au serveur ; le serveur calcule les tronçons de ce sens.
enum SegmentDirection {
  forward('aller', 'Parakou → Cotonou'),
  backward('retour', 'Cotonou → Parakou');

  const SegmentDirection(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Un tronçon de l'accueil. Prix et prochain départ viennent du serveur, rien n'est calculé ici.
class SegmentOffer {
  const SegmentOffer({
    required this.originId,
    required this.origin,
    required this.destinationId,
    required this.destination,
    required this.priceFcfa,
    required this.lineOrigin,
    this.nextDeparture,
  });

  final int originId;
  final String origin;
  final int destinationId;
  final String destination;
  final num priceFcfa;
  final String lineOrigin;

  /// Départ du bus depuis sa ville d'origine ; l'heure de passage aux arrêts intermédiaires n'existe pas.
  final DateTime? nextDeparture;

  factory SegmentOffer.fromJson(Map<String, dynamic> json) => SegmentOffer(
    originId: json['origin_id'] as int,
    origin: json['origin'] as String,
    destinationId: json['destination_id'] as int,
    destination: json['destination'] as String,
    priceFcfa: json['price_fcfa'] as num,
    lineOrigin: json['line_origin'] as String? ?? '',
    nextDeparture: json['next_departure'] == null
        ? null
        : DateTime.parse(json['next_departure'] as String),
  );

  String get label => '$origin → $destination';

  /// Toujours à l'heure du Bénin, quel que soit le fuseau du téléphone.
  String get nextDepartureLabel {
    final departure = nextDeparture;
    if (departure == null) return 'Aucun départ programmé';
    final benin = departure.toUtc().add(beninOffset);
    final day = DateFormat('EEE d MMM', 'fr_FR').format(benin);
    final hour = DateFormat.Hm('fr_FR').format(benin);
    return 'Prochain départ : $day, départ de $lineOrigin à $hour';
  }

  /// Recherche pré-remplie : date du prochain départ, sinon aujourd'hui.
  TripSearch searchFrom({DateTime? now}) => TripSearch(
    originId: originId,
    destinationId: destinationId,
    date: nextDeparture == null ? beninToday(now) : beninToday(nextDeparture),
  );
}
