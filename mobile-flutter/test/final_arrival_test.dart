import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/sales/sale_models.dart';
import 'package:axis_transport_flutter/features/staff/presentation/staff_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Store extends SessionStore {
  @override
  Future<String?> readAccess() async => 'TEST';
}

class _Api extends ApiClient {
  _Api() : super(store: _Store());

  final calls = <int>[];
  String warning = '';

  @override
  Future<Map<String, dynamic>> confirmArrival(int trip, int stop) async {
    calls.add(stop);
    return {'stop': 'TEST', 'warning': warning};
  }
}

const _trip = SaleTrip(
  id: 1,
  label: 'Ville A TEST → Ville C TEST',
  departureAt: null,
  boardingAt: null,
  availableSeats: 10,
  quotes: [],
  stops: [
    RouteStopInfo(id: 1, name: 'Ville A TEST', position: 1),
    RouteStopInfo(id: 2, name: 'Ville B TEST', position: 2),
    RouteStopInfo(id: 3, name: 'Ville C TEST', position: 3),
  ],
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<_Api> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: AxisTheme.light(),
          home: const StaffHomeScreen(activeTrip: _trip),
        ),
      ),
    );
    await _settle(tester);
    return api;
  }

  testWidgets(
    'arrivée finale : confirmation demandée, rien envoyé si annulée',
    (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Arrivée finale à Ville C TEST'));
      await _settle(tester);
      expect(find.text('Terminer le voyage ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await _settle(tester);
      expect(api.calls, isEmpty);

      await tester.tap(find.text('Arrivée finale à Ville C TEST'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('final-arrival-confirm')));
      await _settle(tester);
      expect(api.calls, [3]);
    },
  );

  testWidgets(
    'arrêt intermédiaire : un seul toucher, avertissement du serveur affiché',
    (tester) async {
      final api = await open(tester);
      api.warning = 'Attention : TEST.';
      await tester.tap(find.text('Confirmer l’arrivée à Ville B TEST'));
      await _settle(tester);
      expect(find.text('Terminer le voyage ?'), findsNothing);
      expect(api.calls, [2]);
      expect(find.textContaining('Attention : TEST.'), findsOneWidget);
    },
  );
}

// L'accueil interroge le serveur en boucle (indicateur de chargement) : on avance le temps sans attendre la fin.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
