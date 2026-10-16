import 'dart:convert';

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
  static const _user = 'axis_session_user';

  Future<String> get _owner async =>
      await _storage.read(key: _activeOwner) ?? _guestOwner;

  Future<void> setActiveClient(int userId) =>
      _storage.write(key: _activeOwner, value: 'client:$userId');

  /// Espace local d'un membre du personnel : distinct de celui de tout client du même téléphone.
  Future<void> setActiveStaff(int userId) =>
      _storage.write(key: _activeOwner, value: 'staff:$userId');

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
    await _storage.delete(key: _user);
  }

  /// Profil du client connecté, gardé pour rouvrir la session sans réseau
  /// (billets consultables hors connexion). Effacé à la déconnexion.
  Future<void> cacheUser(User user) =>
      _storage.write(key: _user, value: jsonEncode(user.toJson()));

  Future<User?> readCachedUser() async {
    final raw = await _storage.read(key: _user);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
