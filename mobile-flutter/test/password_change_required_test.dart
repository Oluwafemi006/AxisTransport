import 'dart:convert';
import 'dart:typed_data';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends SessionStore {
  @override
  Future<String?> readAccess() async => 'TEST-jeton';
  @override
  Future<void> setActiveClient(int userId) async {}
  @override
  Future<void> setActiveStaff(int userId) async {}
  @override
  Future<void> cacheUser(User user) async {}
  @override
  Future<User?> readCachedUser() async => null;
  @override
  Future<void> clearTokens() async {}
}

/// Faux serveur : le contrôleur est connecté, puis l'admin réinitialise son mot de passe.
class _Server implements HttpClientAdapter {
  bool resetByAdmin = false;
  int meCalls = 0;

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('/auth/me/')) {
      meCalls++;
      return _json({
        'id': 7, 'username': 'controleur-test', 'first_name': '', 'last_name': '', 'phone': '',
        'role': 'CONTROLLER', 'must_change_password': resetByAdmin,
      }, 200);
    }
    if (resetByAdmin) {
      return _json({'detail': 'Choisissez un nouveau mot de passe avant de continuer.', 'code': 'password_change_required'}, 403);
    }
    return _json({'trips': <dynamic>[]}, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('mot de passe réinitialisé pendant la session : compte relu, écran de changement exigé', () async {
    final server = _Server();
    final api = ApiClient(store: _Store(), dio: Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server);
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(sessionProvider);
    await container.read(sessionProvider.notifier).restore();
    expect(container.read(sessionProvider).user?.mustChangePassword, isFalse);

    server.resetByAdmin = true;
    await expectLater(api.saleOptions(), throwsA(isA<ApiException>()));
    // La relecture du compte se fait en arrière-plan : on lui laisse le temps de répondre.
    for (var i = 0; i < 20 && container.read(sessionProvider).user?.mustChangePassword != true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // must_change_password relu à vrai : le routeur n'autorise plus que l'écran de changement (router.dart).
    expect(container.read(sessionProvider).user?.mustChangePassword, isTrue);
    expect(server.meCalls, greaterThanOrEqualTo(2));
  });
}
