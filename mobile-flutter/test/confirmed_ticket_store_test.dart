import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/offline/data/confirmed_ticket_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Ticket _ticket(int id, String status) => Ticket(
  id: id,
  reference: 'AX-$id',
  trip: Trip(
    id: 5,
    route: const RouteInfo(id: 1, label: 'Cotonou → Bohicon'),
    departureAt: DateTime.utc(2026, 10, 4, 8, 30),
    status: 'SCHEDULED',
    statusDisplay: 'Programmé',
    note: '',
    availableSeats: 20,
  ),
  seat: const Seat(id: 8, number: '3A', status: 'PAID'),
  passengerName: 'Awa Test',
  passengerPhone: '01020304',
  status: status,
  statusDisplay: status,
  qrToken: 'qr-$id',
  amount: 5000,
  currency: 'XOF',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'only issued tickets are stored with complete offline details',
    () async {
      final store = ConfirmedTicketStore(databasePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.replace('client:1', [
        _ticket(1, 'HELD'),
        _ticket(2, 'ISSUED'),
      ]);

      final tickets = await store.read('client:1');
      expect(tickets, hasLength(1));
      expect(tickets.single.id, 2);
      expect(tickets.single.qrToken, 'qr-2');
      expect(tickets.single.trip.route.label, 'Cotonou → Bohicon');
      expect(
        tickets.single.trip.departureAt,
        DateTime.utc(2026, 10, 4, 8, 30).toLocal(),
      );
      expect(tickets.single.passengerName, 'Awa Test');
      expect(tickets.single.seat.number, '3A');
      expect(await store.find('client:1', 1), isNull);
    },
  );

  test(
    'accounts are isolated and server refresh removes old tickets',
    () async {
      final store = ConfirmedTicketStore(databasePath: inMemoryDatabasePath);
      addTearDown(store.close);
      await store.upsert('client:1', _ticket(10, 'ISSUED'));
      await store.upsert('client:2', _ticket(20, 'ISSUED'));
      await store.upsert('client:1', _ticket(11, 'HELD'));

      expect((await store.read('client:1')).map((ticket) => ticket.id), [10]);
      expect((await store.read('client:2')).map((ticket) => ticket.id), [20]);
      expect(await store.read('guest'), isEmpty);

      await store.replace('client:1', [_ticket(10, 'CANCELLED')]);
      expect(await store.read('client:1'), isEmpty);
      expect((await store.read('client:2')).single.id, 20);
    },
  );
}
