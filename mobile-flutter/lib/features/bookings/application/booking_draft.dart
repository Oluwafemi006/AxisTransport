import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../passengers/domain/passenger.dart';
import '../../../core/models.dart';

class BookingDraft {
  const BookingDraft({
    this.trip,
    this.passengers = const [],
    this.seatsByPassenger = const {},
    this.buyerIfu = '',
    this.originId,
    this.destinationId,
    this.originName,
    this.destinationName,
    this.segmentLabel,
    this.boardingPointId,
    this.alightingPointId,
    this.boardingPointName,
    this.alightingPointName,
  });

  final Trip? trip;

  /// IFU de l'acheteur, facultatif : imprimé sur le billet s'il est rempli.
  final String buyerIfu;
  final List<Passenger> passengers;
  final Map<String, Seat> seatsByPassenger;
  final int? originId;
  final int? destinationId;
  final String? originName;
  final String? destinationName;
  final String? segmentLabel;
  final int? boardingPointId;
  final int? alightingPointId;
  final String? boardingPointName;
  final String? alightingPointName;

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
    int? originId,
    int? destinationId,
    String? originName,
    String? destinationName,
    String? segmentLabel,
    int? boardingPointId,
    bool clearBoardingPoint = false,
    int? alightingPointId,
    bool clearAlightingPoint = false,
    String? boardingPointName,
    String? alightingPointName,
  }) => BookingDraft(
    trip: trip ?? this.trip,
    passengers: passengers ?? this.passengers,
    seatsByPassenger: seatsByPassenger ?? this.seatsByPassenger,
    buyerIfu: buyerIfu ?? this.buyerIfu,
    originId: originId ?? this.originId,
    destinationId: destinationId ?? this.destinationId,
    originName: originName ?? this.originName,
    destinationName: destinationName ?? this.destinationName,
    segmentLabel: segmentLabel ?? this.segmentLabel,
    boardingPointId: clearBoardingPoint ? null : (boardingPointId ?? this.boardingPointId),
    alightingPointId: clearAlightingPoint ? null : (alightingPointId ?? this.alightingPointId),
    boardingPointName: clearBoardingPoint ? null : (boardingPointName ?? this.boardingPointName),
    alightingPointName: clearAlightingPoint ? null : (alightingPointName ?? this.alightingPointName),
  );
}

class BookingDraftNotifier extends Notifier<BookingDraft> {
  @override
  BookingDraft build() => const BookingDraft();

  void start(
    Trip trip, {
    int? originId,
    int? destinationId,
    String? originName,
    String? destinationName,
    String? segmentLabel,
  }) {
    if (state.trip?.id == trip.id) {
      state = state.copyWith(
        trip: trip,
        originId: originId ?? state.originId,
        destinationId: destinationId ?? state.destinationId,
        originName: originName ?? state.originName,
        destinationName: destinationName ?? state.destinationName,
        segmentLabel: segmentLabel ?? state.segmentLabel,
      );
      return;
    }
    state = BookingDraft(
      trip: trip,
      originId: originId,
      destinationId: destinationId,
      originName: originName,
      destinationName: destinationName,
      segmentLabel: segmentLabel,
    );
  }

  void setSegment({
    int? originId,
    int? destinationId,
    String? originName,
    String? destinationName,
    String? segmentLabel,
  }) {
    state = state.copyWith(
      originId: originId,
      destinationId: destinationId,
      originName: originName,
      destinationName: destinationName,
      segmentLabel: segmentLabel,
    );
  }

  void setBoardingPoints({
    int? boardingPointId,
    String? boardingPointName,
    int? alightingPointId,
    String? alightingPointName,
  }) {
    state = state.copyWith(
      boardingPointId: boardingPointId,
      clearBoardingPoint: boardingPointId == null,
      boardingPointName: boardingPointName,
      alightingPointId: alightingPointId,
      clearAlightingPoint: alightingPointId == null,
      alightingPointName: alightingPointName,
    );
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
