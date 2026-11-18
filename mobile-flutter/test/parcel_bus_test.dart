import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/parcels/parcels_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('sans position : pas de bus (colis non chargé, livré ou annulé)', () {
    final tracking = ParcelTracking.fromJson({
      'tracking_number': 'AX-COL-TEST',
      'bus': null,
    });
    expect(tracking.bus, isNull);
  });

  test('aucune arrivée : départ prévu à l’heure du Bénin', () {
    final bus = ParcelBus.fromJson({
      'stops': ['Ville A TEST', 'Ville B TEST'],
      'departure_at': '2026-11-18T06:00:00Z',
      'last_stop': null,
      'last_confirmed_at': null,
    });
    expect(
      bus.text,
      startsWith('Aucune arrivée confirmée pour l’instant. Départ prévu le '),
    );
    expect(bus.text, endsWith('07:00.'));
  });

  test('dernière ville confirmée et son heure', () {
    final bus = ParcelBus.fromJson({
      'stops': ['Ville A TEST', 'Ville B TEST'],
      'departure_at': '2026-11-18T07:00:00+01:00',
      'last_stop': 'Ville B TEST',
      'last_confirmed_at': '2026-11-18T09:30:00+01:00',
    });
    expect(
      bus.text,
      startsWith('Dernier passage confirmé : Ville B TEST, le '),
    );
    expect(bus.text, endsWith('09:30.'));
  });

  testWidgets('la ligne met en avant la dernière ville', (tester) async {
    const bus = ParcelBus(
      stops: ['Ville A TEST', 'Ville B TEST', 'Ville C TEST'],
      departureAt: null,
      lastStop: 'Ville B TEST',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ParcelBusLine(bus: bus)),
      ),
    );
    expect(find.text('Position du bus'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('parcel-bus-current')),
        matching: find.text('Ville B TEST'),
      ),
      findsOneWidget,
    );
  });
}
