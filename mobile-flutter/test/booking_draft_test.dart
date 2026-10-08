import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_draft.dart';
import 'package:axis_transport_flutter/features/passengers/domain/passenger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('un siège ne peut appartenir qu’à un passager du brouillon', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(bookingDraftProvider.notifier);
    notifier.start(
      Trip(
        id: 1,
        route: const RouteInfo(id: 1, label: 'Cotonou → Parakou'),
        departureAt: DateTime(2026, 10, 4),
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
    );
    notifier.setPassengers(const [
      Passenger(
        id: 'p1',
        fullName: 'Awa Test',
        phone: '97000001',
        type: PassengerType.adult,
      ),
      Passenger(
        id: 'p2',
        fullName: 'Sena Test',
        phone: '',
        type: PassengerType.child,
      ),
    ]);
    const seat = Seat(id: 1, number: '3A', status: 'AVAILABLE');
    notifier.assignSeat('p1', seat);
    notifier.assignSeat('p2', seat);

    final draft = container.read(bookingDraftProvider);
    expect(draft.seatsByPassenger['p1'], isNull);
    expect(draft.seatsByPassenger['p2']?.number, '3A');
    expect(draft.hasAllSeats, isFalse);
    expect(draft.totalAmount, 10000);
  });
}
