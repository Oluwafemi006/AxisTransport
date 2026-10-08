import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/offline/data/confirmed_ticket_store.dart';
import 'models.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage, ConfirmedTicketStore? tickets})
    : _storage = storage ?? const FlutterSecureStorage(),
      _tickets = tickets ?? ConfirmedTicketStore();

  final FlutterSecureStorage _storage;
  final ConfirmedTicketStore _tickets;

  static const _access = 'axis_access_token';
  static const _refresh = 'axis_refresh_token';
  static const _activeOwner = 'axis_active_ticket_owner';
  static const _legacyTickets = 'axis_cached_tickets';
  static const _guestOwner = 'guest';

  Future<String> get _owner async =>
      await _storage.read(key: _activeOwner) ?? _guestOwner;

  Future<void> setActiveClient(int userId) =>
      _storage.write(key: _activeOwner, value: 'client:$userId');

  Future<String?> readAccess() => _storage.read(key: _access);
  Future<String?> readRefresh() => _storage.read(key: _refresh);

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _access, value: access);
    if (refresh != null) await _storage.write(key: _refresh, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _activeOwner);
    await _storage.delete(key: _legacyTickets);
  }

  Future<List<Ticket>> readCachedTickets() async => _tickets.read(await _owner);

  Future<Ticket?> findCachedTicket(int ticketId) async =>
      _tickets.find(await _owner, ticketId);

  Future<void> cacheTickets(List<Ticket> tickets) async {
    await _tickets.replace(await _owner, tickets);
    await _storage.delete(key: _legacyTickets);
  }

  Future<void> upsertTicket(Ticket ticket) async =>
      _tickets.upsert(await _owner, ticket);
}
