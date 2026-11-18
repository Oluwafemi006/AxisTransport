// Les 16 trajets vendables de la ligne Parakou ↔ Cotonou (backend/apps/core/axis.py : arrêts et tarifs) :
// une ville sans point d'embarquement ne reçoit jamais les points d'une autre ville, ni en liste ni en silence.
import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_draft.dart';
import 'package:axis_transport_flutter/features/passengers/presentation/passengers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MemStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}
}

const _p = BoardingPointInfo.new;

// Identifiants des villes (TEST) et ordre de Parakou vers Cotonou, comme AXIS_STOPS.
const _ids = {'Parakou': 1, 'Savè': 3, 'Glazoué': 4, 'Dassa': 5, 'Bohicon': 6, 'Cotonou': 2};
const _forwardOrder = ['Parakou', 'Savè', 'Glazoué', 'Dassa', 'Bohicon', 'Cotonou'];

// Tronçons tarifés (AXIS_FARES), vendus dans les deux sens : 16 trajets.
const _fares = [
  ['Parakou', 'Cotonou'], ['Parakou', 'Bohicon'], ['Parakou', 'Glazoué'], ['Parakou', 'Dassa'],
  ['Parakou', 'Savè'], ['Savè', 'Cotonou'], ['Savè', 'Bohicon'], ['Bohicon', 'Cotonou'],
];

// Points (TEST) : Parakou 1, Cotonou 2 ; Bohicon selon le cas ; les autres villes aucun.
Map<String, List<BoardingPointInfo>> _points({required bool bohiconHasPoint}) => {
  'Parakou': [_p(id: 101, name: 'TEST Parc Parakou')],
  'Cotonou': [_p(id: 201, name: 'TEST Arrêt Cotonou A'), _p(id: 202, name: 'TEST Arrêt Cotonou B')],
  if (bohiconHasPoint) 'Bohicon': [_p(id: 601, name: 'TEST Arrêt Bohicon')],
};

Trip _trip({required bool forward, required bool bohiconHasPoint}) {
  final points = _points(bohiconHasPoint: bohiconHasPoint);
  final order = forward ? _forwardOrder : _forwardOrder.reversed.toList();
  Place place(String name) => Place(id: _ids[name]!, name: name, address: '', boardingPoints: points[name] ?? const []);
  return Trip(
    id: forward ? 10 : 20,
    route: RouteInfo(
      id: forward ? 1 : 2,
      label: '${order.first} → ${order.last}',
      origin: place(order.first),
      destination: place(order.last),
      stops: [
        for (var i = 0; i < order.length; i++)
          RouteStopInfo(id: _ids[order[i]]!, name: order[i], position: i + 1, boardingPoints: points[order[i]] ?? const []),
      ],
    ),
    departureAt: DateTime(2026, 11, 20, 8, 0),
    status: 'SCHEDULED',
    statusDisplay: 'Programmé',
    note: '',
    availableSeats: 23,
    currentFare: const Fare(id: 1, name: 'TEST', amount: 1000, currency: 'XOF'),
  );
}

class _Api extends ApiClient {
  _Api(this.bohiconHasPoint) : super(store: _MemStore());
  final bool bohiconHasPoint;

  @override
  Future<Trip> trip(int tripId, {int? originId, int? destinationId}) async =>
      _trip(forward: tripId == 10, bohiconHasPoint: bohiconHasPoint);

  @override
  Future<User> me() async => const User(id: 1, username: 'test', firstName: 'TEST', lastName: 'Client', phone: '+22900000000', role: 'CLIENT');
}

Future<void> _checkAll(WidgetTester tester, {required bool bohiconHasPoint}) async {
  final points = _points(bohiconHasPoint: bohiconHasPoint);
  final trips = [for (final f in _fares) ...[[f[0], f[1]], [f[1], f[0]]]];
  expect(trips.length, 16);
  for (final pair in trips) {
    final from = pair[0], to = pair[1];
    final forward = _forwardOrder.indexOf(from) < _forwardOrder.indexOf(to);
    final c = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(_Api(bohiconHasPoint))]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AxisTheme.light(),
        home: PassengersScreen(key: UniqueKey(), tripId: forward ? 10 : 20, passengerCount: 1, originId: _ids[from], destinationId: _ids[to]),
      ),
    ));
    await tester.pumpAndSettle();
    final draft = c.read(bookingDraftProvider);
    final label = '$from → $to (Bohicon ${bohiconHasPoint ? "avec" : "sans"} point)';
    final fromIds = (points[from] ?? const []).map((p) => p.id).toSet();
    final toIds = (points[to] ?? const []).map((p) => p.id).toSet();
    // Point retenu : jamais celui d'une autre ville ; aucun pour une ville sans point ; présélectionné si la ville n'en a qu'un.
    if (fromIds.isEmpty) {
      expect(draft.boardingPointId, isNull, reason: '$label : embarquement');
    } else if (fromIds.length == 1) {
      expect(draft.boardingPointId, fromIds.single, reason: '$label : embarquement');
    } else {
      expect(draft.boardingPointId == null || fromIds.contains(draft.boardingPointId), isTrue, reason: '$label : embarquement');
    }
    if (toIds.isEmpty) {
      expect(draft.alightingPointId, isNull, reason: '$label : débarquement');
    } else if (toIds.length == 1) {
      expect(draft.alightingPointId, toIds.single, reason: '$label : débarquement');
    } else {
      expect(draft.alightingPointId == null || toIds.contains(draft.alightingPointId), isTrue, reason: '$label : débarquement');
    }
    // Liste à choisir seulement pour une ville du trajet qui a plusieurs points (ici Cotonou).
    final expectedLists = [fromIds, toIds].where((ids) => ids.length > 1).length;
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(expectedLists), reason: '$label : listes');
    for (final other in points.entries.where((e) => e.key != from && e.key != to)) {
      for (final point in other.value) {
        expect(find.text(point.name), findsNothing, reason: '$label : point de ${other.key} affiché');
      }
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('16 trajets, Bohicon avec un point : chaque ville garde ses propres points', (tester) async {
    await _checkAll(tester, bohiconHasPoint: true);
  });

  testWidgets('16 trajets, Bohicon sans point (seules Parakou et Cotonou en ont) : aucun point d’une autre ville', (tester) async {
    await _checkAll(tester, bohiconHasPoint: false);
  });
}
