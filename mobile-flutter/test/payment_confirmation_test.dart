import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_checkout.dart';
import 'package:axis_transport_flutter/features/tickets/ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

const _client = User(
  id: 1,
  username: 'awa',
  firstName: 'Awa',
  lastName: '',
  phone: '',
  role: 'CLIENT',
);

Ticket _ticket(String status, {int? bookingId = 77}) => Ticket(
  id: 5,
  reference: 'AX-HELD-5',
  bookingId: bookingId,
  trip: Trip(
    id: 1,
    route: const RouteInfo(id: 1, label: 'Cotonou → Parakou'),
    departureAt: DateTime(2026, 10, 17, 8),
    status: 'SCHEDULED',
    statusDisplay: 'Programmé',
    note: '',
    availableSeats: 3,
  ),
  seat: const Seat(id: 3, number: '1C', status: 'PAID'),
  passengerName: 'Awa Test',
  passengerPhone: '',
  status: status,
  statusDisplay: status,
  qrToken: status == 'ISSUED' ? 'qr-5' : '',
  amount: 1000,
  currency: 'XOF',
);

class _Store extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<Ticket?> findCachedTicket(int ticketId) async => null;
}

/// Faux serveur : le paiement est confirmé chez FedaPay quand [approved] est vrai.
class _Api extends ApiClient {
  _Api({required this.approved}) : super(store: _Store());

  final bool approved;
  final refreshed = <int>[];

  @override
  Future<User> me() async => _client;

  @override
  Future<List<Ticket>> tickets() async => [
    _ticket(refreshed.isNotEmpty && approved ? 'ISSUED' : 'HELD'),
  ];

  @override
  Future<BookingReservation> refreshBookingPayment({
    required int bookingId,
    String? guestAccessToken,
  }) async {
    refreshed.add(bookingId);
    return BookingReservation(
      id: bookingId,
      reference: 'AX-RES-77',
      status: approved ? 'CONFIRMED' : 'HELD',
      statusDisplay: '',
      amount: 1000,
      currency: 'XOF',
      tickets: const [],
    );
  }
}

Future<void> _open(WidgetTester tester, _Api api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        home: TicketScreen(ticketId: 5, initialTicket: _ticket('HELD')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('billet en attente de paiement', () {
    test('seul un billet réservé d\'une réservation peut être vérifié', () {
      expect(_ticket('HELD').awaitsPayment, isTrue);
      expect(_ticket('ISSUED').awaitsPayment, isFalse);
      expect(_ticket('HELD', bookingId: null).awaitsPayment, isFalse);
      final json = _ticket('HELD').toJson();
      expect(json['booking'], 77);
    });

    testWidgets(
      '« Vérifier mon paiement » fait apparaître le billet confirmé',
      (tester) async {
        final api = _Api(approved: true);
        await _open(tester, api);
        expect(find.byType(PrettyQrView), findsNothing);

        await tester.scrollUntilVisible(
          find.text('Vérifier mon paiement'),
          200,
          scrollable: find.byType(Scrollable).first,
        );

        await tester.ensureVisible(find.text('Vérifier mon paiement'));

        await tester.pumpAndSettle();
        await tester.tap(find.text('Vérifier mon paiement'));
        await tester.pumpAndSettle();

        expect(api.refreshed, [77]);
        expect(
          find.text('Paiement confirmé : votre billet est prêt.'),
          findsOneWidget,
        );
        expect(find.byType(PrettyQrView), findsOneWidget);
        expect(find.text('Vérifier mon paiement'), findsNothing);
      },
    );

    testWidgets('paiement encore en attente : message clair, rien d\'émis', (
      tester,
    ) async {
      final api = _Api(approved: false);
      await _open(tester, api);
      await tester.scrollUntilVisible(
        find.text('Vérifier mon paiement'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Vérifier mon paiement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vérifier mon paiement'));
      await tester.pumpAndSettle();

      expect(api.refreshed, [77]);
      expect(
        find.textContaining('pas encore confirmé par FedaPay'),
        findsOneWidget,
      );
      expect(find.byType(PrettyQrView), findsNothing);
    });
  });

  group('vérification patiente au retour de la page de paiement', () {
    test(
      'réessaie tant que FedaPay répond « en attente », puis s\'arrête',
      () async {
        var checks = 0;
        final done = await retryWhilePending(
          stillPending: () async => ++checks < 3,
          active: () => true,
          delay: Duration.zero,
        );
        expect(done, isTrue);
        expect(checks, 3);
      },
    );

    test('abandonne après le nombre d\'essais prévu', () async {
      var checks = 0;
      final done = await retryWhilePending(
        stillPending: () async {
          checks++;
          return true;
        },
        active: () => true,
        attempts: 12,
        delay: Duration.zero,
      );
      expect(done, isFalse);
      expect(checks, 12);
    });

    test('s\'arrête dès que l\'écran est quitté', () async {
      var checks = 0;
      final done = await retryWhilePending(
        stillPending: () async {
          checks++;
          return true;
        },
        active: () => checks < 2,
        delay: Duration.zero,
      );
      expect(done, isFalse);
      expect(checks, 2);
    });
  });
}
