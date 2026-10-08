import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session.dart'; // Pour apiClientProvider
import '../../../core/models.dart';
import '../../passengers/domain/passenger.dart'; // Pour PassengerTypeLabel
import 'booking_draft.dart';

class BookingCheckoutState {
  const BookingCheckoutState({
    required this.methods,
    this.reservation,
  });

  final List<PaymentMethod> methods;
  final BookingReservation? reservation;

  BookingCheckoutState copyWith({
    List<PaymentMethod>? methods,
    BookingReservation? reservation,
  }) {
    return BookingCheckoutState(
      methods: methods ?? this.methods,
      reservation: reservation ?? this.reservation,
    );
  }
}

class BookingCheckoutNotifier
    extends AsyncNotifier<BookingCheckoutState> {
  @override
  Future<BookingCheckoutState> build() async {
    final client = ref.watch(apiClientProvider);
    final allMethods = await client.paymentMethods();
    final methods = allMethods.where((m) => m.active).toList();
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

  Future<Ticket?> pay(PaymentMethod method, {String externalReference = ''}) async {
    final currentState = state;
    final reservation = currentState.value?.reservation;

    if (reservation == null) return null;

    state = const AsyncLoading<BookingCheckoutState>();

    try {
      final client = ref.read(apiClientProvider);
      final paidReservation = await client.payBooking(
        bookingId: reservation.id,
        paymentMethod: method.id,
        guestAccessToken: reservation.guestAccessToken,
        externalReference: externalReference,
      );

      final confirmedTickets =
          paidReservation.tickets.where((item) => item.isConfirmed).toList();

      for (final ticket in confirmedTickets) {
        await client.store.upsertTicket(ticket);
      }

      ref.read(bookingDraftProvider.notifier).clear();

      final firstTicket = confirmedTickets.isEmpty
          ? (paidReservation.tickets.isEmpty ? null : paidReservation.tickets.first)
          : confirmedTickets.first;

      return firstTicket;
    } catch (e, st) {
      state = AsyncError<BookingCheckoutState>(e, st);
      return null;
    }
  }
}

final bookingCheckoutProvider = AsyncNotifierProvider<
    BookingCheckoutNotifier, BookingCheckoutState>(
  BookingCheckoutNotifier.new,
);
