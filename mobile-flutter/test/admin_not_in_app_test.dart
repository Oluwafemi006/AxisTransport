import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/staff/presentation/staff_home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends SessionStore {
  bool cleared = false;

  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<void> setActiveStaff(int userId) async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<User?> readCachedUser() async => null;

  @override
  Future<void> clearTokens() async => cleared = true;
}

class _Api extends ApiClient {
  _Api(this.role, this.store_) : super(store: store_);

  final String role;
  final _Store store_;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() async => store_.clearTokens();

  @override
  Future<User> me() async => User(id: 7, username: 'compte-test', firstName: '', lastName: '', phone: '', role: role);
}

User _user({String first = '', String last = '', required String username}) =>
    User(id: 1, username: username, firstName: first, lastName: last, phone: '', role: 'CONTROLLER');

void main() {
  test('l’application s’identifie par son en-tête', () {
    expect(mobileAppHeader, 'X-Axis-Client');
    expect(mobileAppHeaderValue, 'app-mobile');
  });

  test('le refus du serveur est reconnu par son code', () {
    expect(isAdminRefusal(ApiException('x', statusCode: 403, data: {'code': adminNotAllowedCode})), isTrue);
    expect(isAdminRefusal(ApiException('x', statusCode: 403, data: {'detail': 'autre'})), isFalse);
    expect(isAdminRefusal(Exception('réseau')), isFalse);
  });

  test('un compte ADMIN est déconnecté avec le message, sans entrer dans l’espace contrôleur', () async {
    final store = _Store();
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(_Api('ADMIN', store))]);
    addTearDown(container.dispose);
    final session = container.read(sessionProvider.notifier);
    await expectLater(session.login('compte-test', 'TEST'), throwsA(isA<ApiException>().having((e) => e.message, 'message', adminNotAllowedMessage)));
    expect(container.read(sessionProvider).user, isNull);
    expect(container.read(sessionProvider).adminRefused, isTrue);
    expect(store.cleared, isTrue);
  });

  test('un contrôleur se connecte comme avant', () async {
    final container = ProviderContainer(overrides: [apiClientProvider.overrideWithValue(_Api('CONTROLLER', _Store()))]);
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).login('compte-test', 'TEST');
    expect(container.read(sessionProvider).user?.role, 'CONTROLLER');
    expect(container.read(sessionProvider).adminRefused, isFalse);
  });

  group('Bonjour, … dans l’espace contrôleur', () {
    test('nom s’il existe', () => expect(staffGreetingName(_user(first: 'Prénom', last: 'TEST', username: 'play-controleur')), 'Prénom TEST'));
    test('sinon identifiant sans préfixe technique', () => expect(staffGreetingName(_user(username: 'play-controleur')), 'Controleur'));
    test('identifiant e-mail : partie avant @', () => expect(staffGreetingName(_user(username: 'agent.test@exemple.test')), 'Agent test'));
    test('identifiant simple inchangé', () => expect(staffGreetingName(_user(username: 'Controleur1')), 'Controleur1'));
    test('rien du tout', () => expect(staffGreetingName(null), 'Contrôleur'));
  });
}
