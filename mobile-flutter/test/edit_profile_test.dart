import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _client = User(
  id: 9,
  username: 'TEST.client',
  firstName: 'Awa',
  lastName: 'TEST',
  phone: '',
  role: 'CLIENT',
  email: '',
);

class _Session extends SessionNotifier {
  int restored = 0;
  @override
  SessionState build() => const SessionState(user: _client, ready: true);
  @override
  Future<void> restore() async => restored++;
}

class _Api extends ApiClient {
  Map<String, String>? sent;
  @override
  Future<void> updateProfile(Map<String, String> fields) async => sent = fields;
}

void main() {
  test('contrôles : prénom et téléphone obligatoires, numéro et e-mail vérifiés', () {
    expect(profileFormError(firstName: ' ', phone: '0197000012', email: ''), 'Le prénom est obligatoire.');
    expect(profileFormError(firstName: 'Awa', phone: '', email: ''), 'Le numéro de téléphone est obligatoire.');
    expect(profileFormError(firstName: 'Awa', phone: 'abc', email: ''), 'Numéro de téléphone invalide.');
    expect(profileFormError(firstName: 'Awa', phone: '123', email: ''), 'Numéro de téléphone invalide.');
    expect(profileFormError(firstName: 'Awa', phone: '+229 01 97 00 00 12', email: 'x'), 'Veuillez saisir une adresse e-mail valide.');
    expect(profileFormError(firstName: 'Awa', phone: '+229 01 97 00 00 12', email: ''), isNull);
  });

  Future<(_Api, _Session)> open(WidgetTester tester) async {
    final api = _Api();
    final session = _Session();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api), sessionProvider.overrideWith(() => session)],
      child: MaterialApp(theme: AxisTheme.light(), home: const EditProfileScreen()),
    ));
    await tester.pumpAndSettle();
    return (api, session);
  }

  testWidgets('le formulaire est prérempli ; un numéro vide n’est pas envoyé', (tester) async {
    final (api, _) = await open(tester);
    expect(find.widgetWithText(TextField, 'Awa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('Le numéro de téléphone est obligatoire.'), findsOneWidget);
    expect(api.sent, isNull);
  });

  testWidgets('enregistrement : les 4 champs sont envoyés, puis le compte est relu', (tester) async {
    final (api, session) = await open(tester);
    await tester.enterText(find.byKey(const Key('profile-phone')), ' 01 97 00 00 12 ');
    await tester.enterText(find.byKey(const Key('profile-email')), 'awa.test@exemple.test');
    await tester.tap(find.byKey(const Key('profile-save')));
    await tester.pumpAndSettle();
    expect(api.sent, {'first_name': 'Awa', 'last_name': 'TEST', 'phone': '01 97 00 00 12', 'email': 'awa.test@exemple.test'});
    expect(session.restored, 1);
  });
}
