import 'dart:io';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _TestStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<void> setActiveStaff(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<User?> readCachedUser() async => null;

  @override
  Future<void> clearTokens() async {}

  @override
  Future<Ticket?> findCachedTicket(int ticketId) async => null;
}

class _Phase7Api extends ApiClient {
  _Phase7Api({this.role}) : super(store: _TestStore());

  String? role;

  static const _locOrigin = Place(
    id: 1,
    name: 'VilleTEST-A',
    address: 'Gare TEST A',
  );
  static const _locDest = Place(
    id: 2,
    name: 'VilleTEST-B',
    address: 'Gare TEST B',
  );

  static final _trip = Trip(
    id: 101,
    route: const RouteInfo(
      id: 1,
      label: 'VilleTEST-A → VilleTEST-B',
      origin: _locOrigin,
      destination: _locDest,
    ),
    departureAt: DateTime(2026, 11, 15, 8, 30),
    arrivalAt: DateTime(2026, 11, 15, 13, 0),
    boardingAt: DateTime(2026, 11, 15, 8, 0),
    status: 'SCHEDULED',
    statusDisplay: 'Programmé',
    note: '',
    availableSeats: 12,
    currentFare: const Fare(id: 1, name: 'Standard', amount: 7000, currency: 'FCFA'),
  );

  static final _issuedTicket = Ticket(
    id: 501,
    reference: 'AXS-TEST-501',
    trip: _trip,
    seat: const Seat(id: 12, number: '12', status: 'PAID'),
    passengerName: 'Awa TEST',
    passengerPhone: '+2290197000000',
    status: 'ISSUED',
    statusDisplay: 'Payé · Valide',
    qrToken: 'QR-TEST-501',
    amount: 7000,
    currency: 'FCFA',
    originName: 'VilleTEST-A',
    destinationName: 'VilleTEST-B',
  );

  @override
  Future<void> login(String username, String password) async {
    role = username.contains('ctrl') ? 'CONTROLLER' : 'CLIENT';
  }

  @override
  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String phone,
    String? lastName,
    String? email,
  }) async {
    role = 'CLIENT';
  }

  @override
  Future<User> me() async {
    if (role == null) throw ApiException('Non connecté', statusCode: 401);
    return User(
      id: role == 'CLIENT' ? 10 : 20,
      username: role == 'CLIENT' ? 'client_test' : 'ctrl_test',
      firstName: role == 'CLIENT' ? 'Awa' : 'Koffi',
      lastName: 'TEST',
      phone: '+2290197000000',
      role: role!,
    );
  }

  @override
  Future<List<Place>> locations() async => const [_locOrigin, _locDest];

  @override
  Future<List<Trip>> trips({
    int? originId,
    int? destinationId,
    DateTime? date,
  }) async => [_trip];

  @override
  Future<List<Ticket>> tickets() async => [_issuedTicket];

  @override
  Future<List<BookingReservation>> myBookings() async => const [];

  @override
  Future<Map<String, dynamic>> saleOptions() async => {
    'trips': [
      {
        'id': 101,
        'route_detail': {'label': 'VilleTEST-A → VilleTEST-B'},
        'departure_at': '2026-11-15T08:30:00Z',
        'boarding_at': '2026-11-15T08:00:00Z',
        'available_seats': 12,
        'quotes': [
          {
            'payment_method': 1,
            'code': 'CASH',
            'label': 'Espèces',
            'amount': 7000,
            'fee_amount': 0,
            'total': 7000,
            'currency': 'FCFA',
            'online': false,
          },
          {
            'payment_method': 2,
            'code': 'MOMO',
            'label': 'Mobile Money',
            'amount': 7000,
            'fee_amount': 0,
            'total': 7000,
            'currency': 'FCFA',
            'online': true,
          },
        ],
      },
    ],
  };

  @override
  Future<List<Seat>> seats(int tripId) async => const [
    Seat(id: 12, number: '12', status: 'AVAILABLE'),
  ];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
  });

  group('Phase 7 — Audit statique du code (couleurs, tailles, rayons, prestataires)', () {
    test('aucune couleur, fontSize, rayon numérique ni FedaPay/KKiaPay hors lib/core/theme/', () {
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.replaceAll('\\', '/').startsWith('lib/core/theme/'))
          .toList();

      final colorRe = RegExp(
        r'\bColor\s*\(\s*0x[0-9a-fA-F]+|\bColors\.(?!transparent\b)[a-zA-Z0-9_]+',
      );
      final fontSizeRe = RegExp(r'\bfontSize\s*:');
      final radiusRe = RegExp(
        r'\b(?:BorderRadius|Radius)\.circular\s*\(\s*[0-9]+(?:\.[0-9]+)?\s*\)',
      );
      final providerRe = RegExp(r'fedapay|kkiapay', caseSensitive: false);

      final colorHits = <String>[];
      final fontSizeHits = <String>[];
      final radiusHits = <String>[];
      final providerHits = <String>[];

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (colorRe.hasMatch(line)) colorHits.add('${file.path}:${i + 1}');
          if (fontSizeRe.hasMatch(line)) fontSizeHits.add('${file.path}:${i + 1}');
          if (radiusRe.hasMatch(line)) radiusHits.add('${file.path}:${i + 1}');
          if (providerRe.hasMatch(line)) providerHits.add('${file.path}:${i + 1}');
        }
      }

      expect(colorHits, isEmpty, reason: 'Couleurs en dur détectées : $colorHits');
      expect(fontSizeHits, isEmpty, reason: 'Tailles de police en dur détectées : $fontSizeHits');
      expect(radiusHits, isEmpty, reason: 'Rayons en dur détectés : $radiusHits');
      expect(providerHits, isEmpty, reason: 'Noms de prestataires détectés : $providerHits');
    });
  });

  group('Phase 7 — Refus d\'accès croisé et parcours Client / Contrôleur', () {
    testWidgets(
      'Parcours Client (inscription -> recherche -> billet) et refus d\'accès aux routes contrôleur',
      (tester) async {
        final api = _Phase7Api(role: null);
        resetAxisRouter();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: const AxisTransportApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Non connecté -> écran de connexion, ouverture de l'inscription
        axisRouter.go('/inscription');
        await tester.pumpAndSettle();
        expect(find.text('Créer un compte'), findsOneWidget);

        // Inscription client -> redirigé vers l'accueil client (recherche)
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AxisTransportApp)),
        );
        await container.read(sessionProvider.notifier).register(
          username: 'client_test',
          password: 'password123',
          firstName: 'Awa',
          phone: '+2290197000000',
          lastName: 'TEST',
          email: 'awa@test.bj',
        );
        await tester.pumpAndSettle();

        expect(find.text('Où voyagez-vous aujourd’hui ?'), findsOneWidget);

        // Refus d'accès croisé : le client tente d'ouvrir les routes contrôleur
        for (final staffRoute in ['/staff', '/scanner', '/vendre', '/staff/colis', '/staff/profil']) {
          axisRouter.go(staffRoute);
          await tester.pumpAndSettle();
          expect(
            axisRouter.routeInformationProvider.value.uri.path,
            '/',
            reason: 'Le client doit être redirigé vers / depuis $staffRoute',
          );
        }

        // Ouverture du billet QR client
        axisRouter.go('/billets/ticket/501', extra: _Phase7Api._issuedTicket);
        await tester.pumpAndSettle();
        expect(find.text('Votre billet'), findsOneWidget);
        expect(find.text('N° AXS-TEST-501'), findsOneWidget);
      },
    );

    testWidgets(
      'Parcours Contrôleur (connexion -> scanner -> vente -> colis) et refus d\'accès aux routes client',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = _Phase7Api(role: 'CONTROLLER');
        resetAxisRouter();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: const AxisTransportApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Connecté en tant que contrôleur -> redirigé vers /staff
        expect(find.text('Scanner un billet'), findsOneWidget);
        expect(find.text('Vendre un billet'), findsOneWidget);
        expect(find.text('Enregistrer un colis'), findsOneWidget);

        // Refus d'accès croisé : le contrôleur tente d'ouvrir les routes client
        for (final clientRoute in ['/', '/billets', '/location', '/colis', '/profil']) {
          axisRouter.go(clientRoute);
          await tester.pumpAndSettle();
          expect(
            axisRouter.routeInformationProvider.value.uri.path,
            '/staff',
            reason: 'Le contrôleur doit être redirigé vers /staff depuis $clientRoute',
          );
        }

        // Navigation vers Vente -> Colis
        axisRouter.go('/vendre');
        await tester.pumpAndSettle();
        expect(find.text('Vendre un billet'), findsWidgets);

        axisRouter.go('/staff/colis');
        await tester.pumpAndSettle();
        expect(find.text('Nouveau colis'), findsOneWidget);
        expect(find.text('Enregistrement au départ'), findsOneWidget);
      },
    );
  });
}
