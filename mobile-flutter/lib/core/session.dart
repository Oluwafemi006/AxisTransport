import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class SessionState {
  const SessionState({this.user, this.ready = false});

  final User? user;
  final bool ready;

  SessionState copyWith({User? user, bool? ready, bool clearUser = false}) {
    return SessionState(
      user: clearUser ? null : user ?? this.user,
      ready: ready ?? this.ready,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> restore() async {
    try {
      final user = await _api.me();
      if (!user.isClient) {
        await _api.logout();
        state = const SessionState(ready: true);
        return;
      }
      await _api.store.setActiveClient(user.id);
      await _api.store.cacheUser(user);
      state = SessionState(user: user, ready: true);
    } on ApiException catch (error) {
      // Sans réseau, le client déjà connecté garde l'accès à ses billets enregistrés.
      // Un refus du serveur (session expirée) renvoie en revanche à la connexion.
      final cached = error.isNetwork ? await _api.store.readCachedUser() : null;
      state = SessionState(user: cached?.isClient == true ? cached : null, ready: true);
    } catch (_) {
      state = const SessionState(ready: true);
    }
  }

  Future<void> login(String username, String password) async {
    await _api.login(username, password);
    await restore();
    if (state.user == null) {
      throw ApiException('Cette application est réservée aux comptes clients.');
    }
  }

  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String phone,
  }) async {
    await _api.register(
      username: username,
      password: password,
      firstName: firstName,
      phone: phone,
    );
    await restore();
  }

  Future<void> logout() async {
    await _api.logout();
    state = const SessionState(ready: true);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
