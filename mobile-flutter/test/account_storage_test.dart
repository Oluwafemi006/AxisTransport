import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/offline/data/confirmed_ticket_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Stockage sécurisé en mémoire (remplace le trousseau du téléphone pendant les tests).
class _MemorySecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

Ticket _ticket(int id) => Ticket(
  id: id,
  reference: 'AX-$id',
  trip: Trip(
    id: 5,
    route: const RouteInfo(id: 1, label: 'Cotonou → Parakou'),
    departureAt: DateTime.utc(2026, 10, 20, 7),
    status: 'SCHEDULED',
    statusDisplay: 'Planifié',
    note: '',
    availableSeats: 10,
  ),
  seat: const Seat(id: 8, number: '3A', status: 'PAID'),
  passengerName: 'Awa Test',
  passengerPhone: '',
  status: 'ISSUED',
  statusDisplay: 'Ticket émis',
  qrToken: 'qr-$id',
  amount: 7500,
  currency: 'XOF',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late _MemorySecureStorage secure;
  late ConfirmedTicketStore tickets;
  late SessionStore store;

  setUp(() {
    secure = _MemorySecureStorage();
    tickets = ConfirmedTicketStore(databasePath: inMemoryDatabasePath);
    store = SessionStore(storage: secure, tickets: tickets);
  });
  tearDown(() => tickets.close());

  test('les billets d’un client n’apparaissent jamais pour un agent du même téléphone, et inversement', () async {
    await store.setActiveClient(1);
    await store.upsertTicket(_ticket(10));
    expect((await store.readCachedTickets()).map((item) => item.id), [10]);

    await store.clearTokens();
    await store.setActiveStaff(2);
    expect(await store.readCachedTickets(), isEmpty);
    expect(await store.findCachedTicket(10), isNull);

    await store.upsertTicket(_ticket(20));
    await store.clearTokens();
    await store.setActiveClient(1);
    expect((await store.readCachedTickets()).map((item) => item.id), [10]);
  });

  test(
    'un agent et un client ayant le même numéro de compte restent séparés',
    () async {
      await store.setActiveClient(3);
      await store.upsertTicket(_ticket(30));
      await store.setActiveStaff(3);
      expect(await store.readCachedTickets(), isEmpty);
    },
  );

  test('après déconnexion : plus de jetons, plus de profil, plus d’espace actif ; les billets restent rangés par compte', () async {
    await store.saveTokens(access: 'a', refresh: 'r');
    await store.setActiveClient(1);
    await store.cacheUser(
      const User(
        id: 1,
        username: 'awa',
        firstName: 'Awa',
        lastName: '',
        phone: '',
        role: 'CLIENT',
      ),
    );
    await store.upsertTicket(_ticket(10));

    await store.clearTokens();
    expect(await store.readAccess(), isNull);
    expect(await store.readRefresh(), isNull);
    expect(await store.readCachedUser(), isNull);
    expect(secure.values.keys, isEmpty);
    // Personne de connecté : l'espace « invité » est vide, le billet du client n'y apparaît pas.
    expect(await store.readCachedTickets(), isEmpty);
    // Le billet reste sur le téléphone, rangé sous le compte du client, et revient à sa reconnexion.
    await store.setActiveClient(1);
    expect((await store.readCachedTickets()).map((item) => item.id), [10]);
  });
}
