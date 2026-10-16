import 'package:axis_transport_flutter/core/formatters.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

// Repris de l'app staff : ce qu'affiche le résultat d'un scan.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('le résultat du scan affiche siège, trajet, embarquement et départ du serveur', () {
    final lines = scanTicketLines({
      'passenger_name': 'Awa Test',
      'seat_detail': {'number': '2A'},
      'trip_detail': {
        'route_detail': {'label': 'Cotonou → Parakou'},
        'boarding_at': '2026-10-10T06:30:00Z',
        'departure_at': '2026-10-10T07:00:00Z',
      },
    });
    expect(lines[0], 'Passager : Awa Test');
    expect(lines[1], 'Siège : 2A');
    expect(lines[2], 'Trajet : Cotonou → Parakou');
    expect(
      lines[3],
      'Embarquement : ${formatFullDateTime(DateTime.utc(2026, 10, 10, 6, 30).toLocal())}',
    );
    expect(
      lines[4],
      'Départ : ${formatFullDateTime(DateTime.utc(2026, 10, 10, 7).toLocal())}',
    );
  });

  test(
    'une donnée absente du scan affiche « à confirmer », rien n’est inventé',
    () {
      final lines = scanTicketLines({'passenger_name': 'Awa Test'});
      expect(lines[1], 'Siège : à confirmer');
      expect(lines[3], 'Embarquement : à confirmer');
      expect(lines[4], 'Départ : à confirmer');
    },
  );
}
