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

class _FakeApi extends ApiClient {
  _FakeApi() : super(store: _MemoryStore());

  @override
  Future<List<Trip>> trips() async => [];

  @override
  Future<List<Ticket>> tickets() async => [];

  @override
  Future<List<Place>> locations() async => [];

  @override
  Future<User> me() async => const User(
    id: 1,
    username: 'eddy',
    firstName: 'Eddy',
    lastName: '',
    phone: '',
    role: 'CLIENT',
  );
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

  testWidgets(
    'l’accueil staff ouvre sur le scanner, sans parcours d’achat client',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
          child: const AxisTransportApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ouvrir le Scanner QR'), findsOneWidget);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Scanner'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Où souhaitez-vous aller ?'), findsNothing);
    },
  );

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
