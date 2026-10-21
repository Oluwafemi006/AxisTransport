import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../passengers/domain/passenger.dart';
import '../../../core/models.dart';

class BookingDraft {
  const BookingDraft({
    this.trip,
    this.passengers = const [],
    this.seatsByPassenger = const {},
    this.buyerIfu = '',
  });

  final Trip? trip;

  /// IFU de l'acheteur, facultatif : imprimé sur le billet s'il est rempli.
  final String buyerIfu;
  final List<Passenger> passengers;
  final Map<String, Seat> seatsByPassenger;

  bool get hasAllPassengers =>
      passengers.isNotEmpty &&
      passengers.every((item) => item.fullName.trim().isNotEmpty);

  bool get hasAllSeats =>
      hasAllPassengers &&
      passengers.every((item) => seatsByPassenger.containsKey(item.id));

  num get totalAmount => (trip?.currentFare?.amount ?? 0) * passengers.length;

  BookingDraft copyWith({
    Trip? trip,
    List<Passenger>? passengers,
    Map<String, Seat>? seatsByPassenger,
    String? buyerIfu,
  }) => BookingDraft(
    trip: trip ?? this.trip,
    passengers: passengers ?? this.passengers,
    seatsByPassenger: seatsByPassenger ?? this.seatsByPassenger,
    buyerIfu: buyerIfu ?? this.buyerIfu,
  );
}

class BookingDraftNotifier extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void start(Trip trip) {
    if (state.trip?.id == trip.id) {
      state = state.copyWith(trip: trip);
      return;
    }
    state = BookingDraft(trip: trip);
  }

  void setPassengers(List<Passenger> passengers) {
    final passengerIds = passengers.map((item) => item.id).toSet();
    state = state.copyWith(
      passengers: List.unmodifiable(passengers),
      seatsByPassenger: Map.unmodifiable(
        Map<String, Seat>.from(state.seatsByPassenger)
          ..removeWhere((id, _) => !passengerIds.contains(id)),
      ),
    );
  }

  void assignSeat(String passengerId, Seat seat) {
    final assignments = Map<String, Seat>.from(state.seatsByPassenger);
    assignments.removeWhere(
      (id, assigned) => id != passengerId && assigned.id == seat.id,
    );
    assignments[passengerId] = seat;
    state = state.copyWith(seatsByPassenger: Map.unmodifiable(assignments));
  }

  void unassignSeat(String passengerId) {
    final assignments = Map<String, Seat>.from(state.seatsByPassenger);
    assignments.remove(passengerId);
    state = state.copyWith(seatsByPassenger: Map.unmodifiable(assignments));
  }

  void setBuyerIfu(String value) => state = state.copyWith(buyerIfu: value);

  void clear() => state = const BookingDraft();
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftNotifier, BookingDraft>(
      BookingDraftNotifier.new,
    );
