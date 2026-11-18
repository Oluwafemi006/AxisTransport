// Parcours sans ressaisie : retour depuis les résultats, raccourcis vers les résultats, session expirée.
import 'dart:io';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/auth/login_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Store extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}
}

class _NoSessionApi extends ApiClient {
  _NoSessionApi() : super(store: _Store());
  @override
  Future<User> me() async => throw ApiException('Session TEST absente', statusCode: 401);
}

Future<void> _openLogin(WidgetTester tester, String location) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [GoRoute(path: '/connexion', builder: (_, _) => const LoginScreen())],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(_NoSessionApi())],
    child: MaterialApp.router(theme: AxisTheme.light(), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('connexion après expiration : message en français', (tester) async {
    await _openLogin(tester, '/connexion?expiree=1&retour=%2Fbillets');
    expect(find.byKey(const Key('session-expired-banner')), findsOneWidget);
    expect(find.textContaining('Votre session a expiré'), findsOneWidget);
  });

  testWidgets('connexion ordinaire : aucun message d\'expiration', (tester) async {
    await _openLogin(tester, '/connexion');
    expect(find.byKey(const Key('session-expired-banner')), findsNothing);
  });

  test('session expirée : connexion avec message et écran à retrouver', () {
    final location = Uri.parse(expiredLoginLocation('/billets/booking/12/passagers?origin=1&destination=3'));
    expect(location.path, '/connexion');
    expect(location.queryParameters['expiree'], '1');
    expect(location.queryParameters['retour'], '/billets/booking/12/passagers?origin=1&destination=3');
  });

  test('adresse de retour : chemin interne seulement', () {
    expect(safeReturnLocation('/billets/resultats?origin=1'), '/billets/resultats?origin=1');
    for (final value in [null, '', 'https://pirate.exemple.test', '//pirate.exemple.test', 'billets', '/connexion?retour=/x']) {
      expect(safeReturnLocation(value), isNull, reason: '$value');
    }
  });

  test('l\'état « expiré » prévient le routeur', () {
    final notifier = SessionRouterNotifier();
    var calls = 0;
    notifier.addListener(() => calls++);
    notifier.update(const SessionState(ready: true, user: User(id: 1, username: 'test', firstName: 'TEST', lastName: '', phone: '', role: 'CLIENT')));
    notifier.update(const SessionState(ready: true, expired: true));
    expect(calls, 2);
    expect(notifier.session.expired, isTrue);
  });

  testWidgets('recherche lancée depuis l\'accueil : le retour ramène à l\'accueil, pas à l\'onglet Billets', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                // Même appel que la carte de recherche (trip_search_card.dart).
                onPressed: () => context.push('/billets/resultats?origin=1&destination=3&date=2026-11-19&passagers=1'),
                child: const Text('Rechercher (TEST)'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/billets',
          builder: (_, _) => const Scaffold(body: Text('Onglet Billets')),
          routes: [GoRoute(path: 'resultats', builder: (_, _) => const Scaffold(body: Text('Résultats')))],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(theme: AxisTheme.light(), routerConfig: router));
    await tester.tap(find.text('Rechercher (TEST)'));
    await tester.pumpAndSettle();
    expect(find.text('Résultats'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Rechercher (TEST)'), findsOneWidget);
    expect(find.text('Onglet Billets'), findsNothing);
  });

  test('la carte de recherche et les raccourcis de l\'accueil utilisent push vers les résultats', () async {
    final card = await _read('lib/features/trips/presentation/trip_search_card.dart');
    expect(card.contains('context.push(search.resultsLocation)'), isTrue);
    expect(card.contains('context.go(search.resultsLocation)'), isFalse);
    final home = await _read('lib/features/home/home_screen.dart');
    expect(home.contains('segment.searchFrom().resultsLocation'), isTrue);
  });
}

Future<String> _read(String path) async => File(path).readAsStringSync();
