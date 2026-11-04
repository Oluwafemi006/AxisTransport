import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/photo_slots.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_parcel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Départ Parakou → Cotonou, arrivée confirmée à Savè : le colis part par défaut de Savè.
class _ParcelApi extends ApiClient {
  Map<String, dynamic>? sent;

  @override
  Future<Map<String, dynamic>> saleOptions() async => {
        'parcel_base_fcfa': 2000,
        'trips': [
          {
            'id': 9,
            'route_detail': {
              'label': 'Parakou → Cotonou',
              'stops': [
                {'id': 1, 'name': 'Parakou', 'position': 1},
                {'id': 2, 'name': 'Savè', 'position': 2},
                {'id': 3, 'name': 'Bohicon', 'position': 3},
                {'id': 4, 'name': 'Cotonou', 'position': 4},
              ],
            },
            'arrivals': [2],
            'departure_at': '2026-11-05T07:00:00Z',
            'available_seats': 40,
            'quotes': [],
          },
        ],
      };

  @override
  Future<List<Place>> locations() async => const [];

  @override
  Future<Map<String, dynamic>> createParcel(Map<String, dynamic> fields, List<List<int>> photos) async {
    sent = fields;
    return {'tracking_number': 'TEST-COLIS-1', 'amount': 2000};
  }
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR'));

  testWidgets('Colis : départ = arrêt actuel, destination après lui, récapitulatif puis envoi avec le départ', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = _ParcelApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AxisTheme.light(),
        home: ControllerParcelScreen(
          onCapturePhoto: (_) async => const PhotoSlotItem(id: 'p1', label: 'Photo TEST'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DÉPART DU COLIS *'), findsOneWidget);
    expect(find.text('Savè'), findsOneWidget); // départ par défaut
    expect(find.text('Cotonou'), findsOneWidget); // destination par défaut : terminus

    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    for (var index = 0; index < 4; index++) {
      await tester.enterText(fields.at(index), index.isEven ? 'TEST Nom' : '90000000');
    }
    await tester.enterText(fields.at(4), 'TEST carton');
    await tester.ensureVisible(find.byKey(const Key('parcel-submit')));
    await tester.tap(find.byKey(const Key('parcel-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Confirmer le colis'), findsOneWidget);
    expect(find.textContaining('Colis Savè → Cotonou'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
    // La compression des photos tourne hors du fil d'affichage : on la laisse finir en temps réel.
    for (var step = 0; step < 20 && api.sent == null; step++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(api.sent?['trip'], 9);
    expect(api.sent?['origin'], 2);
    expect(api.sent?['destination'], 4);
  });
}
