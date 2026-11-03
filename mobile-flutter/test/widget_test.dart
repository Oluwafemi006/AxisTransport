import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/tickets/booking_screen.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

class _MemoryStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<User?> readCachedUser() async => null;
}

const _client = User(
  id: 1,
  username: 'eddy',
  firstName: 'Eddy',
  lastName: '',
  phone: '',
  role: 'CLIENT',
);

class _OfflineStore extends _MemoryStore {
  _OfflineStore(this.ticket);

  final Ticket ticket;

  @override
  Future<List<Ticket>> readCachedTickets() async => [ticket];

  @override
  Future<Ticket?> findCachedTicket(int ticketId) async =>
      ticketId == ticket.id ? ticket : null;

  // Client déjà connecté auparavant : sa session se rouvre sans réseau.
  @override
  Future<User?> readCachedUser() async => _client;
}

class _OfflineApi extends ApiClient {
  _OfflineApi(Ticket ticket) : super(store: _OfflineStore(ticket));

  @override
  Future<List<Trip>> trips() async => throw ApiException('Hors connexion');

  @override
  Future<User> me() async => throw ApiException('Hors connexion');

  @override
  Future<List<Place>> locations() async => throw ApiException('Hors connexion');
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
  Future<TripBanner> tripBanner() async => const TripBanner(
    bannerText: '',
    todayTripsCount: 0,
    hasDepartureToday: false,
  );

  @override
  Future<({List<Trip> trips, NextAvailable? nextAvailable})> searchTripsDetailed(
    TripSearch search,
  ) async {
    final t = await searchTrips(search);
    return (trips: t, nextAvailable: null);
  }

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

class _SearchApi extends _FakeApi {
  TripSearch? lastSearch;

  @override
  Future<List<Place>> locations() async => const [
    Place(id: 1, name: 'Cotonou', address: ''),
    Place(id: 2, name: 'Parakou', address: ''),
  ];

  @override
  Future<List<Trip>> searchTrips(TripSearch search) async {
    lastSearch = search;
    return [
      Trip(
        id: 7,
        route: const RouteInfo(
          id: 3,
          label: 'Cotonou → Parakou',
          origin: Place(id: 1, name: 'Cotonou', address: ''),
          destination: Place(id: 2, name: 'Parakou', address: ''),
        ),
        departureAt: DateTime(
          search.date.year,
          search.date.month,
          search.date.day,
          8,
        ),
        status: 'SCHEDULED',
        statusDisplay: 'Programmé',
        note: '',
        availableSeats: 12,
        currentFare: const Fare(
          id: 2,
          name: 'Standard',
          amount: 5000,
          currency: 'XOF',
        ),
      ),
    ];
  }
}

class _BookingApi extends ApiClient {
  _BookingApi() : super(store: _MemoryStore());

  @override
  Future<List<Trip>> trips() async => [
    Trip(
      id: 1,
      route: const RouteInfo(id: 1, label: 'Cotonou → Bohicon'),
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
  Future<Trip> trip(
    int tripId, {
    int? originId,
    int? destinationId,
  }) async => (await trips()).single;

  @override
  Future<List<Seat>> seats(int tripId) async => [
    const Seat(id: 3, number: '3A', status: 'AVAILABLE'),
    const Seat(id: 4, number: '3B', status: 'AVAILABLE'),
  ];

  @override
  Future<List<PaymentMethod>> paymentMethods() async => const [
    PaymentMethod(
      id: 2,
      code: 'FEDAPAY',
      label: 'FedaPay',
      active: true,
      online: true,
    ),
  ];

  // Montant donné par le serveur avant toute réservation : 2 × 5 000, sans frais client (supportés par l'agence).
  @override
  Future<List<PaymentQuote>> tripPaymentQuotes({
    required int tripId,
    int passengers = 1,
    int? originId,
    int? destinationId,
  }) async => [
    PaymentQuote(
      paymentMethod: 2,
      amount: 5000 * passengers,
      feeAmount: 0,
      total: 5000 * passengers,
      currency: 'XOF',
    ),
  ];

  @override
  Future<User> me() async => _client;
}

class _AnonymousBookingApi extends _BookingApi {
  @override
  Future<User> me() async =>
      throw ApiException('Non connecté', statusCode: 401);
}

class _SignedOutApi extends ApiClient {
  _SignedOutApi() : super(store: _MemoryStore());

  @override
  Future<User> me() async =>
      throw ApiException('Non connecté', statusCode: 401);
}

void main() {
  testWidgets(
    'sans compte connecté, seule la connexion ou l’inscription est accessible',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_SignedOutApi())],
          child: const AxisTransportApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Se connecter'), findsOneWidget);
      // Libellés de la maquette Connexion.html (phase 3).
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(find.text('Où voyagez-vous aujourd’hui ?'), findsNothing);
      expect(find.text('Rechercher les trajets'), findsNothing);
      expect(find.text('Billets'), findsNothing);

      await tester.tap(find.text('Créer un compte'));
      await tester.pumpAndSettle();
      expect(find.text('Créer mon compte'), findsOneWidget);
      expect(find.text('Identifiant'), findsOneWidget);
      expect(find.text('Téléphone'), findsOneWidget);
    },
  );

  testWidgets('affiche le parcours client Axis sans espace équipe', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_FakeApi())],
        child: const AxisTransportApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Billets'), findsOneWidget);
    expect(find.text('Colis'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Espace équipe'), findsNothing);
  });

  testWidgets('un billet émis reste consultable avec son QR hors connexion', (
    tester,
  ) async {
    final ticket = Ticket(
      id: 44,
      reference: 'AX-44',
      trip: Trip(
        id: 1,
        route: const RouteInfo(id: 1, label: 'Cotonou → Bohicon'),
        departureAt: DateTime(2026, 10, 4, 9, 30),
        status: 'SCHEDULED',
        statusDisplay: 'Programmé',
        note: '',
        availableSeats: 0,
      ),
      seat: const Seat(id: 3, number: '2A', status: 'PAID'),
      passengerName: 'Awa Test',
      passengerPhone: '',
      status: 'ISSUED',
      statusDisplay: 'Ticket émis',
      qrToken: 'offline-qr-44',
      amount: 5000,
      currency: 'XOF',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_OfflineApi(ticket))],
        child: const AxisTransportApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AX-44'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('AX-44'), findsOneWidget);
    await tester.tap(find.text('AX-44'));
    await tester.pumpAndSettle();
    expect(find.text('Passager : Awa Test'), findsOneWidget);
    expect(find.text('Siège : 2A'), findsOneWidget);
    expect(find.byType(PrettyQrView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('consultable hors connexion'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('consultable hors connexion'), findsOneWidget);
  });

  testWidgets('le siège est proposé après saisie du passager', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Écran isolé, sans nom prérempli par un compte.
        overrides: [
          apiClientProvider.overrideWithValue(_AnonymousBookingApi()),
        ],
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

  testWidgets(
    'la recherche utilise les villes choisies et ouvre les résultats',
    (tester) async {
      axisRouter.go('/');
      final api = _SearchApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: const AxisTransportApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cotonou').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parakou').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rechercher les trajets'));
      await tester.tap(find.text('Rechercher les trajets'));
      await tester.pumpAndSettle();

      expect(api.lastSearch?.originId, 1);
      expect(api.lastSearch?.destinationId, 2);
      expect(find.text('Choisir ce trajet'), findsOneWidget);
      expect(find.text('Cotonou → Parakou'), findsWidgets);
    },
  );

  testWidgets('deux passagers reçoivent deux sièges avant le récapitulatif', (
    tester,
  ) async {
    axisRouter.go('/billets/booking/1/passagers?passagers=2');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_BookingApi())],
        child: const AxisTransportApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('passenger-name-0')),
      'Awa Test',
    );
    await tester.enterText(
      find.byKey(const Key('passenger-phone-0')),
      '97000001',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('passenger-name-1')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('passenger-name-1')),
      'Sena Test',
    );
    await tester.ensureVisible(find.text('Continuer vers les sièges'));
    await tester.tap(find.text('Continuer vers les sièges'));
    await tester.pumpAndSettle();

    expect(find.text('Awa Test'), findsWidgets);
    expect(find.text('Sena Test'), findsWidgets);
    await tester.tap(find.text('3A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3B'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continuer'));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(find.text('Siège 3A'), findsOneWidget);
    expect(find.text('Siège 3B'), findsOneWidget);
    // Une seule action : le montant affiché est celui payé, donné par le serveur avant tout appui.
    expect(find.text('Prix des billets'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^Payer 10\s000 FCFA$')),
      findsOneWidget,
    );
    expect(find.text('Valider et Bloquer les sièges'), findsNothing);
    expect(find.text('Total à payer'), findsNothing);
    expect(find.textContaining('Frais'), findsNothing);
    expect(find.textContaining('réservation atomique'), findsNothing);
  });
}
