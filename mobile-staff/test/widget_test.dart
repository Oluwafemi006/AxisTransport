import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/tickets/booking_screen.dart';
import 'package:axis_transport_flutter/core/formatters.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_scanner_screen.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MemoryStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}
}

/// Faux serveur : `role` nul = personne n'est connecté.
class _FakeApi extends ApiClient {
  _FakeApi({this.role}) : super(store: _MemoryStore());

  String? role;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<User> me() async {
    if (role == null) throw ApiException('Non connecté');
    return User(
      id: 1,
      username: 'agent',
      firstName: 'Awa',
      lastName: '',
      phone: '',
      role: role!,
    );
  }
}

class _BookingApi extends ApiClient {
  _BookingApi() : super(store: _MemoryStore());

  @override
  Future<List<Trip>> trips() async => [
    Trip(
      id: 1,
      route: const RouteInfo(id: 1, label: 'Cotonou → Porto-Novo'),
      departureAt: DateTime(2026, 10, 4, 9, 30),
      status: 'SCHEDULED',
      statusDisplay: 'Programmé',
      note: '',
      availableSeats: 2,
      currentFare: const Fare(
        id: 1,
        name: 'Standard',
        amount: 5000,
        currency: 'XOF',
      ),
    ),
  ];

  @override
  Future<Trip> trip(int tripId) async => (await trips()).single;

  @override
  Future<List<Seat>> seats(int tripId) async => [
    const Seat(id: 3, number: '3A', status: 'AVAILABLE'),
    const Seat(id: 4, number: '3B', status: 'AVAILABLE'),
  ];

  @override
  Future<List<PaymentMethod>> paymentMethods() async => [];

  @override
  Future<User> me() async => throw ApiException('Non connecté');
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  Future<void> pumpApp(WidgetTester tester, _FakeApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const AxisTransportApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sans connexion, seul l’écran de connexion du personnel est accessible',
    (tester) async {
      await pumpApp(tester, _FakeApi());

      expect(find.text('Espace équipe'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Ouvrir le Scanner QR'), findsNothing);
      expect(find.text('Scanner'), findsNothing);
      expect(find.text('Vendre'), findsNothing);
      expect(find.textContaining('Créer un compte'), findsNothing);
    },
  );

  testWidgets(
    'un contrôleur connecté arrive sur l’accueil staff avec le scanner',
    (tester) async {
      await pumpApp(tester, _FakeApi(role: 'CONTROLLER'));

      expect(find.text('Ouvrir le Scanner QR'), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Scanner'), findsOneWidget);
      // L'onglet de vente et son raccourci sont proposés au personnel connecté.
      expect(find.text('Vendre'), findsOneWidget);
      expect(find.text('Vendre un billet'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Où souhaitez-vous aller ?'), findsNothing);
    },
  );

  testWidgets('un compte client est refusé dans l’application staff', (
    tester,
  ) async {
    await pumpApp(tester, _FakeApi(role: 'CLIENT'));
    expect(find.text('Espace équipe'), findsOneWidget);
    expect(find.text('Ouvrir le Scanner QR'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'client');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cette application est réservée au personnel Axis.'),
      findsOneWidget,
    );
    expect(find.text('Ouvrir le Scanner QR'), findsNothing);
  });

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

  testWidgets('le siège est proposé après saisie du passager', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_BookingApi())],
        child: const MaterialApp(home: BookingScreen(tripId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3A'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Awa Test');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('3A'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3A'), findsOneWidget);
  });
}
