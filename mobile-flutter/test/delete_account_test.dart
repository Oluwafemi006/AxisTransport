import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/profile/delete_account_screen.dart';
import 'package:axis_transport_flutter/features/profile/profile_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _client = User(id: 9, username: 'TEST.client', firstName: 'Awa', lastName: 'TEST', phone: '', role: 'CLIENT', email: '');

class _Session extends SessionNotifier {
  String? deletedWith;
  Object? failure;
  @override
  SessionState build() => const SessionState(user: _client, ready: true);
  @override
  Future<void> deleteAccount(String password) async {
    if (failure != null) throw failure!;
    deletedWith = password;
    state = const SessionState(ready: true);
  }
}

Future<_Session> _open(WidgetTester tester, {Object? failure}) async {
  final session = _Session()..failure = failure;
  final router = GoRouter(initialLocation: '/supprimer-compte', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('Accueil TEST')),
    GoRoute(path: '/supprimer-compte', builder: (_, _) => const DeleteAccountScreen()),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionProvider.overrideWith(() => session)],
    child: MaterialApp.router(theme: AxisTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('l’écran dit ce qui est supprimé et ce qui est conservé', (tester) async {
    await _open(tester);
    expect(find.text('Ce qui est supprimé'), findsOneWidget);
    expect(find.text('Ce qui est conservé'), findsOneWidget);
    expect(find.textContaining('pas encore parti'), findsOneWidget);
  });

  testWidgets('sans mot de passe : rien n’est envoyé', (tester) async {
    final session = await _open(tester);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Saisissez votre mot de passe pour confirmer.'), findsOneWidget);
    expect(session.deletedWith, isNull);
  });

  testWidgets('mot de passe saisi : compte supprimé, retour à l’accueil', (tester) async {
    final session = await _open(tester);
    await tester.enterText(find.byKey(const Key('delete-password')), 'TEST-Mdp-42');
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(session.deletedWith, 'TEST-Mdp-42');
    expect(find.text('Accueil TEST'), findsOneWidget);
  });

  testWidgets('refus du serveur (voyage payé à venir) : message affiché, l’écran reste', (tester) async {
    await _open(tester, failure: ApiException('Vous avez un billet payé pour un voyage qui n’est pas encore parti.'));
    await tester.enterText(find.byKey(const Key('delete-password')), 'TEST-Mdp-42');
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-error')), findsOneWidget);
    expect(find.textContaining('pas encore parti'), findsWidgets);
  });

  testWidgets('À propos : liens vers les pages publiques si l’adresse du site est connue', (tester) async {
    await tester.pumpWidget(MaterialApp(home: const AboutScreen(siteUrl: 'https://exemple.test')));
    expect(find.byKey(const Key('about-privacy')), findsOneWidget);
    expect(find.byKey(const Key('about-deletion')), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: const AboutScreen(siteUrl: '')));
    expect(find.byKey(const Key('about-privacy')), findsNothing);
  });
}
