import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Écouteur pour que GoRouter puisse réagir aux changements de session.
class SessionRouterNotifier extends ChangeNotifier {
  SessionState _session = const SessionState();
  SessionState get session => _session;

  void update(SessionState newSession) {
    if (_session.user?.id != newSession.user?.id ||
        _session.user?.role != newSession.user?.role ||
        _session.ready != newSession.ready ||
        _session.expired != newSession.expired ||
        _session.adminRefused != newSession.adminRefused) {
      _session = newSession;
      notifyListeners();
    }
  }
}

final sessionRouterNotifier = SessionRouterNotifier();

class SessionState {
  const SessionState({
    this.user,
    this.ready = false,
    this.expired = false,
    this.adminRefused = false,
  });

  final User? user;
  final bool ready;

  /// Vrai quand la session vient d'expirer pendant l'utilisation (et non à l'ouverture de l'application).
  final bool expired;

  /// Vrai quand un compte administrateur vient d'être refusé : la connexion affiche le message.
  final bool adminRefused;

  SessionState copyWith({User? user, bool? ready, bool clearUser = false}) {
    return SessionState(
      user: clearUser ? null : user ?? this.user,
      ready: ready ?? this.ready,
      expired: expired,
      adminRefused: adminRefused,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Session perdue en cours d'utilisation : retour à la connexion avec un message (voir globalRoleRedirect).
    _api.onSessionLost = _sessionLost;
    _api.onPasswordChangeRequired = _passwordChangeRequired;
    Future.microtask(restore);
    sessionRouterNotifier.update(const SessionState());
    return const SessionState();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> restore() async {
    try {
      // L'interface affichée dépend uniquement du rôle renvoyé par le serveur.
      final user = await _api.me();
      // Un administrateur n'utilise jamais l'application (le serveur refuse aussi sa connexion).
      if (user.isAdmin) {
        await _api.logout();
        state = const SessionState(ready: true, adminRefused: true);
        sessionRouterNotifier.update(state);
        return;
      }
      if (!user.isClient && !user.isStaff) {
        await _api.logout();
        state = const SessionState(ready: true);
        sessionRouterNotifier.update(state);
        return;
      }
      if (user.isStaff) {
        await _api.store.setActiveStaff(user.id);
      } else {
        await _api.store.setActiveClient(user.id);
      }
      await _api.store.cacheUser(user);
      state = SessionState(user: user, ready: true);
      sessionRouterNotifier.update(state);
    } on ApiException catch (error) {
      // Sans réseau, le compte déjà connecté sur ce téléphone retrouve son interface (et, pour un
      // client, ses billets enregistrés). Un refus du serveur (session expirée) renvoie à la connexion.
      final cached = error.isNetwork ? await _api.store.readCachedUser() : null;
      final known = cached != null && (cached.isClient || cached.isStaff);
      state = SessionState(user: known ? cached : null, ready: true);
      sessionRouterNotifier.update(state);
    } catch (_) {
      state = const SessionState(ready: true);
      sessionRouterNotifier.update(state);
    }
  }

  bool _rereading = false;

  /// Relit le compte (GET /auth/me/ reste permis) : must_change_password passe à vrai et le routeur
  /// ouvre l'écran de changement de mot de passe. Un seul relecture à la fois.
  Future<void> _passwordChangeRequired() async {
    if (_rereading || state.user == null || state.user!.mustChangePassword) return;
    _rereading = true;
    try {
      await restore();
    } finally {
      _rereading = false;
    }
  }

  void _sessionLost() {
    if (state.user == null) return;
    if (_api.lastLossWasAdminRefusal) {
      _api.lastLossWasAdminRefusal = false;
      state = const SessionState(ready: true, adminRefused: true);
      sessionRouterNotifier.update(state);
      return;
    }
    state = const SessionState(ready: true, expired: true);
    sessionRouterNotifier.update(state);
  }

  Future<void> login(String username, String password) async {
    await _api.login(username, password);
    await restore();
    if (state.adminRefused) throw ApiException(adminNotAllowedMessage);
    if (state.user == null) {
      throw ApiException('Ce compte ne peut pas utiliser l\'application.');
    }
  }

  Future<void> register({
    required String phone,
    required String password,
    String? email,
  }) async {
    await _api.register(phone: phone, password: password, email: email);
    await restore();
  }

  Future<void> deleteAccount(String password) async {
    await _api.deleteAccount(password);
    state = const SessionState(ready: true);
    sessionRouterNotifier.update(state);
  }

  Future<void> logout() async {
    await _api.logout();
    state = const SessionState(ready: true);
    sessionRouterNotifier.update(state);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
