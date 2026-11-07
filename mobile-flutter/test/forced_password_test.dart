import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/features/auth/forced_password_screen.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  String? current;
  String? next;
  @override
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    current = currentPassword;
    next = newPassword;
  }
}

class _Session extends SessionNotifier {
  int restored = 0;
  @override
  SessionState build() => const SessionState(ready: true);
  @override
  Future<void> restore() async => restored++;
}

void main() {
  test('le modèle lit « doit changer son mot de passe » (absent = non)', () {
    final base = {'id': 1, 'username': 'TEST', 'role': 'COUNTER'};
    expect(User.fromJson(base).mustChangePassword, isFalse);
    expect(User.fromJson({...base, 'must_change_password': true}).mustChangePassword, isTrue);
    expect(User.fromJson({...base, 'must_change_password': true}).toJson()['must_change_password'], isTrue);
  });

  test('l’écran imposé a sa propre adresse', () {
    expect(forcedPasswordPath, '/mot-de-passe-obligatoire');
  });

  Future<(_Api, _Session)> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final api = _Api();
    final session = _Session();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), sessionProvider.overrideWith(() => session)],
      child: const MaterialApp(home: ForcedPasswordScreen()),
    ));
    return (api, session);
  }

  testWidgets('mots de passe différents : rien n’est envoyé', (tester) async {
    final (api, _) = await open(tester);
    await tester.enterText(find.byKey(const Key('forced-current')), 'TEST-provisoire');
    await tester.enterText(find.byKey(const Key('forced-new')), 'TEST-Mdp-42');
    await tester.enterText(find.byKey(const Key('forced-confirm')), 'TEST-autre');
    await tester.tap(find.byKey(const Key('forced-save')));
    await tester.pump();
    expect(find.text('Les deux mots de passe ne correspondent pas.'), findsOneWidget);
    expect(api.next, isNull);
  });

  testWidgets('changement envoyé, puis compte relu pour lever l’obligation', (tester) async {
    final (api, session) = await open(tester);
    await tester.enterText(find.byKey(const Key('forced-current')), 'TEST-provisoire');
    await tester.enterText(find.byKey(const Key('forced-new')), 'TEST-Mdp-42');
    await tester.enterText(find.byKey(const Key('forced-confirm')), 'TEST-Mdp-42');
    await tester.tap(find.byKey(const Key('forced-save')));
    await tester.pump();
    expect((api.current, api.next), ('TEST-provisoire', 'TEST-Mdp-42'));
    expect(session.restored, 1);
  });
}
