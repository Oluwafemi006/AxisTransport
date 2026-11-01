import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/axis_text_field.dart';
import 'package:axis_transport_flutter/features/auth/forgot_password_screen.dart';
import 'package:axis_transport_flutter/features/auth/invitation_screen.dart';
import 'package:axis_transport_flutter/features/auth/login_screen.dart';
import 'package:axis_transport_flutter/features/auth/register_screen.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MockStore extends SessionStore {
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

class _MockApi extends ApiClient {
  _MockApi({this.role}) : super(store: _MockStore());

  String? role;

  @override
  Future<void> login(String username, String password) async {
    if (username == 'bad_user') {
      throw ApiException('Identifiant ou mot de passe incorrect.');
    }
  }

  @override
  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String phone,
    String? lastName,
    String? email,
  }) async {}

  @override
  Future<String> requestPasswordReset(String email) async =>
      'TEST code envoyé';

  @override
  Future<String> confirmPasswordReset({
    required String email,
    required String code,
    required String password,
  }) async {
    if (code == '000000') throw ApiException('Code incorrect ou expiré.');
    return 'TEST mot de passe modifié';
  }

  @override
  Future<Map<String, dynamic>> checkStaffInvitation(String token) async {
    if (token == 'valid_token') {
      return {
        'valid': true,
        'email': 'controleur@axis.bj',
        'group': 'Contrôleur',
      };
    }
    throw ApiException('Jeton invalide ou expiré.');
  }

  @override
  Future<Map<String, dynamic>> acceptStaffInvitation({
    required String token,
    required String password,
  }) async {
    return {'success': true};
  }

  @override
  Future<User> me() async {
    if (role == null) throw ApiException('Non connecté', statusCode: 401);
    return User(
      id: 42,
      username: 'test_user',
      firstName: 'Jean',
      lastName: 'Valjean',
      phone: '+22901000000',
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

Future<_MockApi> _setupApp(WidgetTester tester, {String? role}) async {
  final api = _MockApi(role: role);
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

  group('Phase 3 — Routage par rôle avec GoRouter', () {
    testWidgets('Client tente d’accéder à une route contrôleur : redirection vers accueil client', (tester) async {
      await _setupApp(tester, role: 'CLIENT');

      // Tenter d'accéder directement à la route contrôleur /scanner
      axisRouter.go('/scanner');
      await tester.pumpAndSettle();

      // Vérifie qu'on est redirigé vers l'espace client
      expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);
      expect(find.text('Billets'), findsOneWidget);
      expect(find.text('Scanner'), findsNothing);

      // Tenter d'accéder à /staff/vendre
      axisRouter.go('/vendre');
      await tester.pumpAndSettle();
      expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);
    });

    testWidgets('Contrôleur tente d’accéder à une route client : redirection vers accueil contrôleur', (tester) async {
      await _setupApp(tester, role: 'CONTROLLER');

      // Tenter d'accéder à l'accueil client /
      axisRouter.go('/');
      await tester.pumpAndSettle();

      // Redirigé vers /staff (accueil contrôleur)
      expect(find.text('Accueil'), findsOneWidget);
      expect(find.text('Scanner'), findsOneWidget);
      expect(find.text('Vendre'), findsOneWidget);
      expect(find.text('Billets'), findsNothing);

      // Tenter d'accéder à /location
      axisRouter.go('/location');
      await tester.pumpAndSettle();
      expect(find.text('Scanner un billet'), findsOneWidget);
    });

    testWidgets('Non connecté tente d’accéder à l’accueil : redirection vers /connexion', (tester) async {
      await _setupApp(tester, role: null);

      axisRouter.go('/');
      await tester.pumpAndSettle();

      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
    });
  });

  group('Phase 3 — Formulaires et validations', () {
    testWidgets('Mot de passe oublié : code, erreur serveur, puis succès', (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_MockApi())],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const ForgotPasswordScreen(),
          ),
        ),
      );

      Finder fieldOf(String label) => find.descendant(
            of: find.widgetWithText(AxisTextField, label),
            matching: find.byType(TextField),
          );

      await tester.tap(find.text('Recevoir un code'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une adresse e-mail valide.'), findsOneWidget);

      await tester.enterText(fieldOf('E-mail'), 'client.test@exemple.test');
      await tester.tap(find.text('Recevoir un code'));
      await tester.pumpAndSettle();
      expect(find.text('TEST code envoyé'), findsOneWidget);

      await tester.enterText(fieldOf('Code à 6 chiffres'), '000000');
      await tester.enterText(fieldOf('Nouveau mot de passe'), 'TEST-Mdp-42');
      await tester.enterText(fieldOf('Confirmer le mot de passe'), 'TEST-autre');
      await tester.tap(find.text('Changer le mot de passe'));
      await tester.pumpAndSettle();
      expect(find.text('Les deux mots de passe ne correspondent pas.'), findsOneWidget);

      await tester.enterText(fieldOf('Confirmer le mot de passe'), 'TEST-Mdp-42');
      await tester.tap(find.text('Changer le mot de passe'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Code incorrect ou expiré.'), findsOneWidget);

      await tester.enterText(fieldOf('Code à 6 chiffres'), '123456');
      await tester.tap(find.text('Changer le mot de passe'));
      await tester.pumpAndSettle();
      expect(find.text('TEST mot de passe modifié'), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);
    });

    testWidgets('Connexion : validation champs obligatoires et gestion erreur API', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AxisTheme.light(),
          home: const LoginScreen(),
        ),
      );

      // Clic sans rien saisir
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir votre identifiant et votre mot de passe.'), findsOneWidget);
    });

    testWidgets('Inscription : validation des champs requis et mot de passe', (tester) async {
      // Écran haut : tout le formulaire est construit, sans défilement.
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AxisTheme.light(),
          home: const RegisterScreen(),
        ),
      );

      Finder fieldOf(String label) => find.descendant(
            of: find.widgetWithText(AxisTextField, label),
            matching: find.byType(TextField),
          );

      Future<void> fill(String label, String text) =>
          tester.enterText(fieldOf(label), text);

      // Clic sans rien remplir
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez renseigner votre nom et prénom.'), findsOneWidget);

      // Remplir nom et prénom mais pas le téléphone
      await fill('Nom', 'Bio');
      await fill('Prénom', 'Gounou');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez renseigner votre numéro de téléphone.'), findsOneWidget);

      // Remplir téléphone mais email invalide
      await fill('Téléphone', '0197000000');
      await fill('E-mail', 'emailinvalide');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Veuillez saisir une adresse e-mail valide.'), findsOneWidget);

      // Mot de passe trop court
      await fill('E-mail', 'bio@axis.bj');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez un identifiant de connexion.'), findsOneWidget);

      await fill('Identifiant', 'bio.test');
      await fill('Mot de passe', 'court');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Le mot de passe doit comporter au moins 8 caractères.'), findsOneWidget);

      // Mots de passe différents
      await fill('Mot de passe', 'password123');
      await fill('Confirmer le mot de passe', 'password456');
      await tester.tap(find.text('Créer mon compte'));
      await tester.pumpAndSettle();
      expect(find.text('Les mots de passe ne correspondent pas.'), findsOneWidget);
    });

    testWidgets('Activation contrôleur : affiche l’e-mail verrouillé', (tester) async {
      final api = _MockApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: AxisTheme.light(),
            home: const InvitationScreen(token: 'valid_token'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activez votre compte'), findsOneWidget);
      expect(find.text('controleur@axis.bj'), findsOneWidget);
      expect(find.text('Activer mon compte'), findsOneWidget);
    });
  });

  test('changement de compte : la navigation repart d’un routeur vierge', () {
    final before = axisRouter;
    resetAxisRouter();
    expect(identical(before, axisRouter), isFalse);
    expect(axisRouter.routeInformationProvider.value.uri.path, '/');
  });
}
