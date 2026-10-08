import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session.dart'; // Pour apiClientProvider
import '../../../core/models.dart';
import '../../passengers/domain/passenger.dart'; // Pour PassengerTypeLabel
import 'booking_draft.dart';

class BookingCheckoutState {
  const BookingCheckoutState({
    required this.methods,
    this.reservation,
    this.checkout,
    this.busy = false,
    this.error,
  });

  final List<PaymentMethod> methods;
  final BookingReservation? reservation;

  /// Transaction de paiement créée par le serveur, en attente de confirmation.
  final PaymentCheckout? checkout;
  final bool busy;
  final String? error;

  BookingCheckoutState copyWith({
    BookingReservation? reservation,
    PaymentCheckout? checkout,
    bool clearCheckout = false,
    bool? busy,
    String? error,
  }) {
    return BookingCheckoutState(
      methods: methods,
      reservation: reservation ?? this.reservation,
      checkout: clearCheckout ? null : (checkout ?? this.checkout),
      busy: busy ?? false,
      error: error,
    );
  }
}

class BookingCheckoutNotifier
    extends AsyncNotifier<BookingCheckoutState> {
  @override
  Future<BookingCheckoutState> build() async {
    final client = ref.watch(apiClientProvider);
    final allMethods = await client.paymentMethods();
    // Seuls les moyens payables en ligne sont proposés dans l'application.
    final methods = allMethods.where((m) => m.active && m.online).toList();
    return BookingCheckoutState(methods: methods);
  }

  Future<void> reserve(BookingDraft draft) async {
    if (!draft.hasAllSeats || draft.trip == null) return;

    final currentState = state;
    state = const AsyncLoading<BookingCheckoutState>();

    try {
      final client = ref.read(apiClientProvider);

      final contactPhone = draft.passengers
          .map((item) => item.phone.trim())
          .firstWhere((phone) => phone.isNotEmpty, orElse: () => '');

      final reservation = await client.reserveBooking(
        trip: draft.trip!.id,
        contactPhone: contactPhone,
        passengers: draft.passengers.map((passenger) {
          final seat = draft.seatsByPassenger[passenger.id]!;
          return {
            'full_name': passenger.fullName,
            'phone': passenger.phone,
            'passenger_type': passenger.type.apiValue,
            'seat': seat.id,
          };
        }).toList(),
      );

      final methods = currentState.value?.methods ?? [];
      state = AsyncData(
        BookingCheckoutState(methods: methods, reservation: reservation),
      );
    } catch (e, st) {
      state = AsyncError<BookingCheckoutState>(e, st);
    }
  }

  /// Crée la transaction chez le prestataire. Le montant vient du serveur.
  Future<PaymentCheckout?> startPayment(PaymentMethod method) async {
    final current = state.value;
    final reservation = current?.reservation;
    if (current == null || reservation == null) return null;

    state = AsyncData(current.copyWith(busy: true));
    try {
      final checkout = await ref.read(apiClientProvider).checkoutBooking(
            bookingId: reservation.id,
            paymentMethod: method.id,
            guestAccessToken: reservation.guestAccessToken,
          );
      state = AsyncData(current.copyWith(checkout: checkout));
      return checkout;
    } catch (e) {
      state = AsyncData(current.copyWith(error: e.toString()));
      return null;
    }
  }

  /// Demande au serveur de vérifier le paiement et d'émettre les billets.
  /// La réservation et la transaction sont conservées si le paiement n'est pas encore confirmé.
  Future<Ticket?> pay() async {
    final current = state.value;
    final reservation = current?.reservation;
    final checkout = current?.checkout;
    if (current == null || reservation == null || checkout == null) return null;

    state = AsyncData(current.copyWith(busy: true));
    try {
      final client = ref.read(apiClientProvider);
      final paidReservation = await client.payBooking(
        bookingId: reservation.id,
        paymentMethod: checkout.quote.paymentMethod,
        guestAccessToken: reservation.guestAccessToken,
        externalReference: checkout.transactionId,
      );

      final confirmedTickets =
          paidReservation.tickets.where((item) => item.isConfirmed).toList();

      for (final ticket in confirmedTickets) {
        await client.store.upsertTicket(ticket);
      }

      ref.read(bookingDraftProvider.notifier).clear();
      state = AsyncData(current.copyWith(clearCheckout: true));

      return confirmedTickets.isEmpty ? null : confirmedTickets.first;
    } catch (e) {
      state = AsyncData(current.copyWith(error: e.toString()));
      return null;
    }
  }
}

final bookingCheckoutProvider = AsyncNotifierProvider<
    BookingCheckoutNotifier, BookingCheckoutState>(
  BookingCheckoutNotifier.new,
);
