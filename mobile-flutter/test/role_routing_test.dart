import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/widgets/axis_bottom_nav.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:axis_transport_flutter/features/sales/sell_ticket_screen.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_scanner_screen.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Stockage en mémoire qui retient l'espace local actif (client ou personnel).
class _Store extends SessionStore {
  String? owner;

  @override
  Future<void> setActiveClient(int userId) async => owner = 'client:$userId';

  @override
  Future<void> setActiveStaff(int userId) async => owner = 'staff:$userId';

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<User?> readCachedUser() async => null;

  @override
  Future<void> clearTokens() async => owner = null;
}

/// Faux serveur : `role` nul = personne n'est connecté ; `/auth/me/` renvoie ce rôle.
class _Api extends ApiClient {
  _Api({this.role}) : super(store: _Store());

  String? role;

  _Store get memory => store as _Store;

  @override
  Future<void> login(String username, String password) async {}

  @override
  Future<void> logout() => store.clearTokens();

  @override
  Future<User> me() async {
    if (role == null) throw ApiException('Non connecté', statusCode: 401);
    return User(
      id: 7,
      username: 'agent',
      firstName: 'Awa',
      lastName: '',
      phone: '',
      role: role!,
    );
  }

  @override
  Future<List<Trip>> trips() async => [];

  @override
  Future<List<Ticket>> tickets() async => [];

  @override
  Future<List<Place>> locations() async => [];

  @override
  Future<Map<String, dynamic>> saleOptions() async => {'trips': <dynamic>[]};
}

Future<_Api> _open(WidgetTester tester, {String? role}) async {
  final api = _Api(role: role);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const AxisTransportApp(),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets(
    'un client arrive sur l’interface client, sans Scanner ni Vendre',
    (tester) async {
      final api = await _open(tester, role: 'CLIENT');
      expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);
      expect(find.text('Billets'), findsOneWidget);
      expect(find.text('Colis'), findsOneWidget);
      expect(find.text('Scanner'), findsNothing);
      expect(find.text('Vendre'), findsNothing);
      expect(find.text('Scanner un billet'), findsNothing);
      expect(api.memory.owner, 'client:7');
    },
  );

  for (final role in ['CONTROLLER', 'COUNTER', 'ADMIN']) {
    testWidgets('un compte $role arrive sur l’interface du personnel', (
      tester,
    ) async {
      final api = await _open(tester, role: role);
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Scanner'), findsOneWidget);
      expect(find.text('Vendre'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Scanner un billet'), findsOneWidget);
      // Aucun écran d'achat client dans l'interface du personnel.
      expect(find.text('Billets'), findsNothing);
      expect(find.text('Colis'), findsNothing);
      expect(find.text('Où souhaitez-vous aller ?'), findsNothing);
      expect(api.memory.owner, 'staff:7');
    });
  }

  testWidgets('écran secondaire ouvert : la barre du bas disparaît, elle revient au retour', (tester) async {
    await _open(tester, role: 'CLIENT');
    expect(find.byType(AxisBottomNav), findsOneWidget);
    for (final location in ['/billets/recherche', '/mon-profil', '/a-propos']) {
      axisRouter.push(location);
      await tester.pumpAndSettle();
      expect(find.byType(AxisBottomNav), findsNothing, reason: location);
      axisRouter.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AxisBottomNav), findsOneWidget, reason: location);
    }
  });

  testWidgets(
    'la caméra n’est pas ouverte au lancement : le scanner n’est construit qu’à son ouverture',
    (tester) async {
      await _open(tester, role: 'CONTROLLER');
      expect(find.byType(ControllerScannerScreen), findsNothing);
      expect(find.byType(SellTicketScreen), findsNothing);
    },
  );

  testWidgets(
    'sans connexion, seul l’écran de connexion s’affiche (avec l’inscription client)',
    (tester) async {
      await _open(tester);
      expect(find.text('Scanner'), findsNothing);
      expect(find.text('Vendre'), findsNothing);
      expect(find.text('Où souhaitez-vous aller ?'), findsNothing);
      expect(find.byType(TextField), findsWidgets);
    },
  );

  testWidgets('un rôle inconnu du serveur n’ouvre aucune interface', (
    tester,
  ) async {
    final api = await _open(tester, role: 'INCONNU');
    expect(find.text('Scanner'), findsNothing);
    expect(find.text('Où souhaitez-vous aller ?'), findsNothing);
    expect(api.memory.owner, isNull);
  });

  testWidgets(
    'déconnexion du personnel : retour à la connexion, espace local refermé',
    (tester) async {
      final api = await _open(tester, role: 'CONTROLLER');
      await tester.tap(find.text('Profil'));
      await tester.pumpAndSettle();
      expect(find.text('Rôle : Contrôleur'), findsOneWidget);
      api.role = null;
      // Libellé « Déconnexion » en bas du menu du profil (lot profil et paramètres).
      await tester.scrollUntilVisible(find.text('Déconnexion'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Déconnexion'));
      await tester.pumpAndSettle();
      expect(find.text('Scanner'), findsNothing);
      expect(api.memory.owner, isNull);
    },
  );
}
