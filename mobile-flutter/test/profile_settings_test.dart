import 'dart:io';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/app_lock.dart';
import 'package:axis_transport_flutter/core/app_version.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/profile/connection_settings_screen.dart';
import 'package:axis_transport_flutter/features/profile/profile_menu.dart';
import 'package:axis_transport_flutter/features/staff/presentation/staff_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _agent = User(
  id: 3,
  username: 'TEST.guichet',
  firstName: 'Awa',
  lastName: 'TEST',
  phone: '0197000012',
  role: 'COUNTER',
  email: '',
);

class _FakeGate implements BiometricGate {
  _FakeGate({this.isAvailable = true});
  bool isAvailable;
  bool accepts = true;
  int asked = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return accepts;
  }
}

class _MemoryPrefs implements AppLockPrefs {
  bool value = false;
  @override
  Future<bool> read() async => value;
  @override
  Future<void> write(bool enabled) async => value = enabled;
}

class _LoggedIn extends SessionNotifier {
  int logouts = 0;
  @override
  SessionState build() => const SessionState(user: _agent, ready: true);
  @override
  Future<void> logout() async {
    logouts++;
    state = const SessionState(ready: true);
  }
}

class _Api extends ApiClient {
  _Api({this.contacts = const {'phone': '', 'whatsapp': ''}});
  final Map<String, String> contacts;

  @override
  Future<Map<String, dynamic>> saleSummary() async => {
        'scanned_tickets': 4,
        'sold_tickets': 7,
        'parcels': 2,
        'cash_fcfa': 15000,
        'mobile_money_fcfa': 7500,
      };

  @override
  Future<Map<String, String>> contact() async => contacts;
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR'));

  test('la version d’« À propos » est celle de pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim(), appVersion);
  });

  test('numéro masqué : seuls les 2 derniers chiffres restent ; vide si absent', () {
    expect(maskPhone('01 97 00 00 12'), '••••••••12');
    expect(maskPhone(''), '');
  });

  test('adresse du site déduite de « api.domaine » seulement, jamais inventée', () {
    expect(siteUrlFromApi('https://api.exemple.test/api/v1'), 'https://exemple.test');
    expect(siteUrlFromApi('http://127.0.0.1:8000/api/v1'), '');
  });

  group('verrouillage biométrique', () {
    ProviderContainer container(_FakeGate gate, _MemoryPrefs prefs, _LoggedIn session) {
      final c = ProviderContainer(overrides: [
        biometricGateProvider.overrideWithValue(gate),
        appLockPrefsProvider.overrideWithValue(prefs),
        sessionProvider.overrideWith(() => session),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('désactivé par défaut ; activation refusée sans biométrie disponible', () async {
      final prefs = _MemoryPrefs();
      final c = container(_FakeGate(isAvailable: false), prefs, _LoggedIn());
      expect(c.read(appLockProvider).enabled, isFalse);
      final error = await c.read(appLockProvider.notifier).enable();
      expect(error, contains('Aucune empreinte'));
      expect(prefs.value, isFalse);
    });

    test('activation après une reconnaissance, verrou au retour après le délai seulement', () async {
      final prefs = _MemoryPrefs();
      final c = container(_FakeGate(), prefs, _LoggedIn());
      c.read(sessionProvider);
      expect(await c.read(appLockProvider.notifier).enable(), isNull);
      expect(prefs.value, isTrue);
      final lock = c.read(appLockProvider.notifier);
      final t0 = DateTime(2026, 11, 6, 10);
      lock.paused(t0);
      lock.resumed(t0.add(const Duration(seconds: 30)));
      expect(c.read(appLockProvider).locked, isFalse);
      lock.paused(t0);
      lock.resumed(t0.add(appLockDelay));
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('biométrie refusée : l’application reste verrouillée ; mot de passe = déconnexion', () async {
      final gate = _FakeGate();
      final session = _LoggedIn();
      final c = container(gate, _MemoryPrefs(), session);
      c.read(sessionProvider);
      await c.read(appLockProvider.notifier).enable();
      final lock = c.read(appLockProvider.notifier);
      lock.paused(DateTime(2026));
      lock.resumed(DateTime(2026).add(appLockDelay));
      gate.accepts = false;
      expect(await lock.unlock(), isFalse);
      expect(c.read(appLockProvider).locked, isTrue);
      await lock.usePassword();
      expect(session.logouts, 1);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    testWidgets('écran : interrupteur désactivé, message si la biométrie manque', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          biometricGateProvider.overrideWithValue(_FakeGate(isAvailable: false)),
          appLockPrefsProvider.overrideWithValue(_MemoryPrefs()),
          sessionProvider.overrideWith(_LoggedIn.new),
        ],
        child: MaterialApp(theme: AxisTheme.light(), home: const ConnectionSettingsScreen()),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('biometric-switch'))).value, isFalse);
      await tester.tap(find.byKey(const Key('biometric-switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('biometric-message')), findsOneWidget);
    });
  });

  testWidgets('profil du personnel : en-tête, résumé du serveur, menu ; aide masquée sans contact', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api()),
        sessionProvider.overrideWith(_LoggedIn.new),
      ],
      child: MaterialApp(theme: AxisTheme.light(), home: const StaffProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Awa TEST'), findsOneWidget);
    expect(find.text('Identifiant : TEST.guichet'), findsOneWidget);
    expect(find.text('Rôle : Guichetier'), findsOneWidget);
    expect(find.text('Téléphone : ••••••••12'), findsOneWidget);
    expect(find.text('Billets vendus : 7 · Billets scannés : 4'), findsOneWidget);
    expect(find.text('Colis enregistrés : 2'), findsOneWidget);
    expect(find.text('Paramètres de connexion'), findsOneWidget);
    expect(find.text('À propos'), findsOneWidget);
    expect(find.text('Déconnexion'), findsOneWidget);
    expect(find.text('Aide et suggestions'), findsNothing);
  });

  testWidgets('aide affichée quand l’admin a saisi un contact', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api(contacts: const {'phone': '+229 TEST', 'whatsapp': ''})),
        sessionProvider.overrideWith(_LoggedIn.new),
      ],
      child: MaterialApp(theme: AxisTheme.light(), home: const StaffProfileScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Aide et suggestions'), findsOneWidget);
  });
}
