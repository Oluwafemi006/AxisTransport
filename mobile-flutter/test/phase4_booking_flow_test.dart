import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/widgets.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_draft.dart';
import 'package:axis_transport_flutter/features/bookings/presentation/booking_review_screen.dart';
import 'package:axis_transport_flutter/features/home/home_screen.dart';
import 'package:axis_transport_flutter/features/passengers/domain/passenger.dart';
import 'package:axis_transport_flutter/features/passengers/presentation/passengers_screen.dart';
import 'package:axis_transport_flutter/features/seats/presentation/seat_selection_screen.dart';
import 'package:axis_transport_flutter/features/tickets/ticket_screen.dart';
import 'package:axis_transport_flutter/features/trips/domain/segment_offer.dart';
import 'package:axis_transport_flutter/features/trips/domain/trip_search.dart';
import 'package:axis_transport_flutter/features/trips/presentation/trip_results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

class _MemStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<Ticket?> findCachedTicket(int ticketId) async => null;
}

class _Phase4Api extends ApiClient {
  _Phase4Api({this.failNetwork = false}) : super(store: _MemStore());

  final bool failNetwork;

  @override
  Future<User> me() async => const User(
    id: 1,
    username: 'koffi',
    firstName: 'Koffi',
    lastName: 'Mensah',
    phone: '+2290197000000',
    role: 'CLIENT',
  );

  @override
  Future<List<Place>> locations() async {
    if (failNetwork) throw ApiException('Hors connexion');
    return const [
      Place(id: 1, name: 'Parakou', address: ''),
      Place(id: 2, name: 'Cotonou', address: ''),
    ];
  }

  @override
  Future<List<Trip>> trips() async {
    if (failNetwork) throw ApiException('Hors connexion');
    return [_sampleTrip];
  }

  @override
  Future<List<SegmentOffer>> segments(SegmentDirection direction) async {
    if (failNetwork) throw ApiException('Hors connexion');
    return const [
      SegmentOffer(
        originId: 1,
        origin: 'Parakou',
        destinationId: 3,
        destination: 'Savè',
        priceFcfa: 4500,
        lineOrigin: 'Parakou',
      ),
    ];
  }

  /// Comme le serveur : tarif du tronçon demandé, sinon celui du parcours entier.
  @override
  Future<Trip> trip(int tripId, {int? originId, int? destinationId}) async {
    if (originId != 1 || destinationId != 3) return _sampleTrip;
    return Trip(
      id: _sampleTrip.id,
      route: _sampleTrip.route,
      departureAt: _sampleTrip.departureAt,
      status: _sampleTrip.status,
      statusDisplay: _sampleTrip.statusDisplay,
      note: _sampleTrip.note,
      availableSeats: _sampleTrip.availableSeats,
      currentFare: const Fare(
        id: 2,
        name: 'TEST tronçon',
        amount: 4500,
        currency: 'XOF',
      ),
    );
  }

  @override
  Future<List<Trip>> searchTrips(TripSearch search) async {
    if (failNetwork) throw ApiException('Hors connexion');
    return [_sampleTrip];
  }

  @override
  Future<List<Seat>> seats(int tripId) async {
    if (failNetwork) throw ApiException('Hors connexion');
    return const [
      Seat(id: 1, number: '1A', status: 'AVAILABLE', row: 1, column: 1),
      Seat(id: 2, number: '1B', status: 'PAID', row: 1, column: 2),
      Seat(id: 3, number: '1C', status: 'AVAILABLE', row: 1, column: 3),
      Seat(id: 4, number: '1D', status: 'AVAILABLE', row: 1, column: 4),
    ];
  }

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

  @override
  Future<List<PaymentQuote>> tripPaymentQuotes({
    required int tripId,
    int passengers = 1,
    int? originId,
    int? destinationId,
  }) async => [
    PaymentQuote(
      paymentMethod: 2,
      amount: 7500 * passengers,
      feeAmount: 0,
      total: 7500 * passengers,
      currency: 'XOF',
    ),
  ];

  @override
  Future<List<Ticket>> tickets() async => [];
}

final _sampleTrip = Trip(
  id: 10,
  route: const RouteInfo(
    id: 1,
    label: 'Parakou → Cotonou',
    origin: Place(id: 1, name: 'Parakou', address: ''),
    destination: Place(id: 2, name: 'Cotonou', address: ''),
    stops: [
      RouteStopInfo(id: 1, name: 'Parakou', position: 1),
      RouteStopInfo(id: 3, name: 'Savè', position: 2),
      RouteStopInfo(id: 2, name: 'Cotonou', position: 3),
    ],
  ),
  departureAt: DateTime(2026, 10, 30, 8, 0),
  status: 'SCHEDULED',
  statusDisplay: 'Programmé',
  note: '',
  availableSeats: 23,
  vehicleName: 'Bus Climatisé',
  currentFare: const Fare(
    id: 1,
    name: 'Standard',
    amount: 7500,
    currency: 'XOF',
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Phase 4 — Refonte des 5 écrans du parcours de réservation', () {
    testWidgets('1. Accueil + recherche (Main.html) : bandeau, services et recherche', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const Scaffold(body: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);
      expect(find.text('Embarquement 30 min avant le départ'), findsOneWidget);
      expect(find.text('Louer un véhicule'), findsOneWidget);
      expect(find.text('Suivre un colis'), findsOneWidget);
      expect(find.text('Mes billets'), findsOneWidget);
      expect(find.text('Rechercher les trajets'), findsOneWidget);
      expect(find.byType(AxisLogo), findsOneWidget);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pump();
      expect(find.text('Aucune notification'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Parakou → Savè'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Parakou → Savè'), findsOneWidget);
    });

    testWidgets('2. Résultats (Resultats.html) : embarquement (départ - 30 min), RouteStopsBar et StatusChip', (
      tester,
    ) async {
      final search = TripSearch(
        originId: 1,
        destinationId: 2,
        date: DateTime(2026, 10, 30),
        passengers: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: TripResultsScreen(search: search),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('Embarquement 07:30'), findsOneWidget);
      expect(find.byType(RouteStopsBar), findsOneWidget);
      expect(find.text('23 places libres'), findsOneWidget);
      expect(find.text('Choisir ce trajet'), findsOneWidget);
      expect(find.text('Départ de Parakou à 08:00'), findsOneWidget);
      expect(find.textContaining('TTC'), findsNothing);
    });

    testWidgets('2a. Résultats depuis un arrêt intermédiaire : aucune heure de passage inventée', (
      tester,
    ) async {
      final search = TripSearch(
        originId: 3,
        destinationId: 2,
        date: DateTime(2026, 10, 30),
        passengers: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: TripResultsScreen(search: search),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Départ de Parakou à 08:00'), findsOneWidget);
      expect(find.textContaining('Embarquement 07:30'), findsNothing);
    });

    testWidgets('2b. Résultats (Resultats.html) : erreur réseau affiche EmptyState et bouton Réessayer', (
      tester,
    ) async {
      final search = TripSearch(
        originId: 1,
        destinationId: 2,
        date: DateTime(2026, 10, 30),
        passengers: 1,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(_Phase4Api(failNetwork: true)),
          ],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: TripResultsScreen(search: search),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('2c. Passagers : le brouillon garde le tarif du tronçon choisi, pas celui du parcours entier', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
      );
      addTearDown(container.dispose);

      // Brouillon périmé au prix du parcours entier : la réponse du serveur prime.
      container.read(bookingDraftProvider.notifier).start(_sampleTrip);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const PassengersScreen(
              tripId: 10,
              originId: 1,
              destinationId: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final draft = container.read(bookingDraftProvider);
      expect(draft.trip?.currentFare?.amount, 4500);
      expect(draft.originId, 1);
      expect(draft.destinationId, 3);
    });

    testWidgets('3. Choix du siège (Siege.html) : SeatMap alimenté par les sièges API', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
      );
      addTearDown(container.dispose);

      container.read(bookingDraftProvider.notifier).start(_sampleTrip);
      container.read(bookingDraftProvider.notifier).setPassengers(const [
        Passenger(
          id: 'p1',
          fullName: 'Koffi Mensah',
          phone: '97000000',
          type: PassengerType.adult,
        ),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const SeatSelectionScreen(tripId: 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choisissez votre siège'), findsOneWidget);
      expect(find.byType(SeatMap), findsOneWidget);
      expect(find.text('Aucun siège choisi'), findsOneWidget);

      await tester.tap(find.text('1A'));
      await tester.pumpAndSettle();

      expect(find.text('Siège 1A · 1 passager'), findsOneWidget);
      expect(find.text('Continuer'), findsOneWidget);
    });

    testWidgets('4. Récapitulatif + paiement (Recap.html) : Mobile Money et aucune mention de taxe', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
      );
      addTearDown(container.dispose);

      container.read(bookingDraftProvider.notifier).start(_sampleTrip);
      container.read(bookingDraftProvider.notifier).setPassengers(const [
        Passenger(
          id: 'p1',
          fullName: 'Koffi Mensah',
          phone: '97000000',
          type: PassengerType.adult,
        ),
      ]);
      container.read(bookingDraftProvider.notifier).assignSeat(
        'p1',
        const Seat(id: 1, number: '1A', status: 'AVAILABLE'),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const BookingReviewScreen(tripId: 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Récapitulatif'), findsOneWidget);
      expect(find.text('Mobile Money'), findsOneWidget);
      expect(find.text('Validation sur votre téléphone'), findsOneWidget);
      expect(find.text('FedaPay'), findsNothing);
      expect(
        find.textContaining('Le billet est émis'),
        findsOneWidget,
      );
      expect(find.textContaining('TVA'), findsNothing);
      expect(find.textContaining('TTC'), findsNothing);
      expect(find.text('Siège 1A'), findsOneWidget);
    });

    testWidgets('5. Billet QR (Billet.html) : carte d’embarquement, QR, embarquement et mentions légales', (
      tester,
    ) async {
      final ticket = Ticket(
        id: 99,
        reference: 'AX-2026-00142',
        trip: _sampleTrip,
        seat: const Seat(id: 1, number: '1A', status: 'PAID'),
        passengerName: 'Koffi Mensah',
        passengerPhone: '97000000',
        status: 'ISSUED',
        statusDisplay: 'Ticket émis',
        qrToken: 'qr-token-test-99',
        amount: 7500,
        currency: 'XOF',
        printInfo: const TicketPrintInfo(
          paid: true,
          paymentMode: 'Mobile Money',
          priceInclTax: 7500,
          agency: AgencyInfo(
            legalName: 'TEST Transport SARL',
            ifu: 'TEST-IFU-001',
            rccm: 'TEST-RCCM-001',
          ),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase4Api())],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: TicketScreen(ticketId: 99, initialTicket: ticket),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Votre billet'), findsOneWidget);
      expect(find.text('Payé · Valide'), findsOneWidget);
      expect(find.text('PARAKOU'), findsOneWidget);
      expect(find.text('COTONOU'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
      expect(find.byType(PrettyQrView), findsOneWidget);
      expect(find.text('N° AX-2026-00142'), findsOneWidget);
      expect(find.textContaining('TVA'), findsNothing);
      expect(find.textContaining('TTC'), findsNothing);
      expect(
        find.text('Raison sociale : TEST Transport SARL'),
        findsOneWidget,
      );
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Partager'), findsOneWidget);
    });
  });
}

