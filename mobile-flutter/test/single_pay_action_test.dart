import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_checkout.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_draft.dart';
import 'package:axis_transport_flutter/features/passengers/domain/passenger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _fedapay = PaymentMethod(
  id: 2,
  code: 'FEDAPAY',
  label: 'FedaPay',
  active: true,
  feePercentage: 1.8,
  online: true,
);
const _quote = PaymentQuote(
  paymentMethod: 2,
  amount: 1000,
  feeAmount: 18,
  total: 1018,
  currency: 'XOF',
);

class _Store extends SessionStore {}

/// Faux serveur qui compte les appels : sert à vérifier qu'une seule réservation est créée.
class _Api extends ApiClient {
  _Api() : super(store: _Store());

  int reservations = 0;
  int checkouts = 0;
  int cancellations = 0;
  bool failCheckout = false;
  int? cancelledBooking;

  @override
  Future<List<PaymentMethod>> paymentMethods() async => [_fedapay];

  @override
  Future<List<PaymentQuote>> tripPaymentQuotes({
    required int tripId,
    int passengers = 1,
    int? originId,
    int? destinationId,
  }) async => [_quote];

  @override
  Future<BookingReservation> reserveBooking({
    required int trip,
    required String contactPhone,
    String contactEmail = '',
    String buyerIfu = '',
    String? origin,
    String? destination,
    required List<Map<String, dynamic>> passengers,
  }) async {
    reservations += 1;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return BookingReservation(
      id: 40 + reservations,
      reference: 'AX-RES-TEST$reservations',
      status: 'HELD',
      statusDisplay: 'Réservation temporaire',
      amount: 1000,
      currency: 'XOF',
      tickets: const [],
      paymentQuotes: const [_quote],
      reservationExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<PaymentCheckout> checkoutBooking({
    required int bookingId,
    required int paymentMethod,
    String? guestAccessToken,
  }) async {
    checkouts += 1;
    if (failCheckout) throw ApiException('Impossible de contacter FedaPay.');
    return PaymentCheckout(
      transactionId: '900$checkouts',
      paymentUrl: 'https://paiement.exemple.test/x',
      quote: _quote,
    );
  }

  @override
  Future<void> cancelBooking({
    required int bookingId,
    String? guestAccessToken,
  }) async {
    cancellations += 1;
    cancelledBooking = bookingId;
  }
}

BookingDraft _draft() {
  const passenger = Passenger(
    id: 'p1',
    fullName: 'Awa Test',
    phone: '90000000',
    type: PassengerType.adult,
  );
  return BookingDraft(
    trip: Trip(
      id: 1,
      route: const RouteInfo(id: 1, label: 'Cotonou → Parakou'),
      departureAt: DateTime(2026, 10, 10, 8),
      status: 'SCHEDULED',
      statusDisplay: 'Planifié',
      note: '',
      availableSeats: 4,
      currentFare: const Fare(
        id: 1,
        name: 'Standard',
        amount: 1000,
        currency: 'XOF',
      ),
    ),
    passengers: const [passenger],
    seatsByPassenger: const {
      'p1': Seat(id: 3, number: '3A', status: 'AVAILABLE'),
    },
  );
}

Future<(ProviderContainer, _Api, BookingCheckoutNotifier)> _setUp() async {
  final api = _Api();
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  await container.read(bookingCheckoutProvider.future);
  return (container, api, container.read(bookingCheckoutProvider.notifier));
}

void main() {
  test('le total à payer vient du serveur avant toute réservation', () async {
    final (container, api, notifier) = await _setUp();
    await notifier.loadQuotes(tripId: 1, passengers: 1);
    final state = container.read(bookingCheckoutProvider).value!;
    expect(state.tripQuotes.single.total, 1018);
    expect(state.reservation, isNull);
    expect(api.reservations, 0);
  });

  test('une seule action réserve les sièges puis crée le paiement', () async {
    final (container, api, notifier) = await _setUp();
    final checkout = await notifier.payNow(_draft(), _fedapay);
    expect(checkout?.paymentUrl, isNotNull);
    expect((api.reservations, api.checkouts), (1, 1));
    final state = container.read(bookingCheckoutProvider).value!;
    expect(state.reservation?.id, 41);
    expect(state.phase, PaymentPhase.awaiting);
  });

  test('un double appui ne crée qu’une réservation', () async {
    final (_, api, notifier) = await _setUp();
    final results = await Future.wait([
      notifier.payNow(_draft(), _fedapay),
      notifier.payNow(_draft(), _fedapay),
    ]);
    expect(api.reservations, 1);
    expect(api.checkouts, 1);
    expect(results.where((item) => item != null).length, 1);
  });

  test('si le paiement ne démarre pas, la réservation est gardée et le réessai la réutilise', () async {
    final (container, api, notifier) = await _setUp();
    api.failCheckout = true;
    expect(await notifier.payNow(_draft(), _fedapay), isNull);
    var state = container.read(bookingCheckoutProvider).value!;
    expect(state.paymentFailed, isTrue);
    expect(state.reservation?.id, 41);
    expect(state.error, contains('FedaPay'));

    api.failCheckout = false;
    final checkout = await notifier.payNow(_draft(), _fedapay);
    expect(checkout, isNotNull);
    state = container.read(bookingCheckoutProvider).value!;
    // Même réservation : aucune seconde réservation n'a été créée.
    expect(api.reservations, 1);
    expect(state.reservation?.id, 41);
    expect(state.paymentFailed, isFalse);
  });

  test('l’annulation appelle le serveur et libère l’écran pour une nouvelle réservation', () async {
    final (container, api, notifier) = await _setUp();
    await notifier.loadQuotes(tripId: 1, passengers: 1);
    await notifier.payNow(_draft(), _fedapay);
    expect(await notifier.cancel(), isTrue);
    expect((api.cancellations, api.cancelledBooking), (1, 41));
    final state = container.read(bookingCheckoutProvider).value!;
    expect(state.reservation, isNull);
    expect(state.checkout, isNull);
    // Le total reste affichable pour repayer sans recalcul local.
    expect(state.tripQuotes.single.total, 1018);
  });

  test('sans réservation en cours, l’annulation ne fait rien', () async {
    final (_, api, notifier) = await _setUp();
    expect(await notifier.cancel(), isFalse);
    expect(api.cancellations, 0);
  });
}
