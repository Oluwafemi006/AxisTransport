import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/timeline_steps.dart';
import 'package:axis_transport_flutter/features/parcels/parcels_screen.dart';
import 'package:axis_transport_flutter/features/rentals/rentals_screen.dart';
import 'package:axis_transport_flutter/main.dart';
import 'package:axis_transport_flutter/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_audit.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Phase5MemoryStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}

  @override
  Future<List<Ticket>> readCachedTickets() async => [];

  @override
  Future<void> cacheTickets(List<Ticket> tickets) async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<User?> readCachedUser() async => null;
}

class _Phase5FakeApi extends ApiClient {
  _Phase5FakeApi({
    List<Vehicle>? vehicles,
  })  : _vehicles = vehicles ??
            const [
              Vehicle(
                id: 1,
                name: 'Toyota Corolla TEST',
                category: 'Berline',
                capacity: 5,
                state: 'AVAILABLE',
                description: 'Climatisée',
                dailyRate: 25000,
                dailyRateWithDriver: 35000,
                driverAvailable: true,
                baseLocation: Place(id: 1, name: 'Cotonou', address: ''),
              ),
              Vehicle(
                id: 2,
                name: 'Toyota Hiace 15 places TEST',
                category: 'Minibus',
                capacity: 15,
                state: 'AVAILABLE',
                description: 'Bagages',
                dailyRate: 65000,
                driverAvailable: true,
                onlyWithDriver: true,
                baseLocation: Place(id: 1, name: 'Cotonou', address: ''),
              ),
            ],
        super(store: _Phase5MemoryStore());

  final List<Vehicle> _vehicles;
  int? lastCreatedVehicleId;
  bool? lastCreatedWithDriver;
  String? lastTrackedCode;

  @override
  Future<User> me() async => const User(
        id: 10,
        username: 'client_test',
        firstName: 'Koffi',
        lastName: 'Test',
        phone: '+2290197000000',
        role: 'CLIENT',
      );

  @override
  Future<List<Trip>> trips() async => [];

  @override
  Future<List<Ticket>> tickets() async => [];

  @override
  Future<List<Place>> locations() async => [];

  @override
  Future<List<Vehicle>> rentalVehicles() async => _vehicles;

  @override
  Future<List<RentalBooking>> rentals() async => [];

  @override
  Future<RentalBooking> createRental({
    required int vehicle,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool withDriver,
  }) async {
    lastCreatedVehicleId = vehicle;
    lastCreatedWithDriver = withDriver;
    final vehicleObj = _vehicles.firstWhere((v) => v.id == vehicle);
    return RentalBooking(
      id: 99,
      reference: 'LOC-TEST-99',
      vehicle: vehicleObj,
      startsAt: startsAt,
      endsAt: endsAt,
      withDriver: withDriver,
      status: 'PENDING',
      statusDisplay: 'En attente',
    );
  }

  @override
  Future<ParcelTracking> trackParcel(String code) async {
    lastTrackedCode = code;
    if (code == 'INCONNU') {
      throw ApiException('Aucun colis trouvé pour ce code.', statusCode: 404);
    }
    return ParcelTracking(
      trackingNumber: code,
      origin: 'Cotonou',
      destination: 'Parakou',
      steps: [
        ParcelStep(
          label: 'Déposé à l’agence de Cotonou',
          done: true,
          current: false,
          reachedAt: DateTime(2026, 4, 19, 7, 10),
        ),
        ParcelStep(
          label: 'En route vers Parakou',
          done: true,
          current: true,
          reachedAt: DateTime(2026, 4, 19, 8, 5),
        ),
        const ParcelStep(
          label: 'Arrivé à l’agence de Parakou',
          done: false,
          current: false,
        ),
        const ParcelStep(
          label: 'Remis au destinataire',
          done: false,
          current: false,
        ),
      ],
    );
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Audit des largeurs (320, 360, 390 ; texte 1,0 et 1,3)', () {
    Widget app(Widget home) => ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase5FakeApi())],
          child: MaterialApp(theme: AxisTheme.light(), home: home),
        );
    const vehicle = Vehicle(
      id: 1, name: 'Toyota Corolla TEST', category: 'Berline', capacity: 5, state: 'AVAILABLE',
      description: 'Climatisée', dailyRate: 25000, dailyRateWithDriver: 35000, driverAvailable: true,
      baseLocation: Place(id: 1, name: 'Cotonou', address: ''),
    );
    final screens = <String, Widget Function()>{
      'locations': () => app(const RentalsScreen()),
      'demande de location': () => app(const RentalDetailScreen(vehicle: vehicle, initialWithDriver: false)),
      'colis (client)': () => app(const ParcelsScreen()),
    };
    for (final entry in screens.entries) {
      testWidgets('${entry.key} : aucun débordement', (tester) async {
        expect(await layoutOverflows(tester, entry.value), isEmpty);
      });
    }
  });

  group('Phase 5 — Location de véhicules (Location.html & LocationDetail.html)', () {
    testWidgets(
      'SegmentedToggle Sans/Avec chauffeur change les prix et gère le véhicule "Avec chauffeur uniquement"',
      (tester) async {
        final api = _Phase5FakeApi();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: const RentalsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mode initial : Sans chauffeur
        expect(find.text('Location de véhicules'), findsOneWidget);
        expect(find.text('Toyota Corolla TEST'), findsOneWidget);
        expect(find.text('Toyota Hiace 15 places TEST'), findsOneWidget);
        expect(find.textContaining('25'), findsWidgets);

        // Le minibus "Avec chauffeur uniquement" affiche son badge et le bouton "Voir avec chauffeur"
        expect(find.text('Avec chauffeur uniquement'), findsOneWidget);
        expect(find.text('non disponible sans chauffeur'), findsOneWidget);
        expect(find.text('Voir avec chauffeur'), findsOneWidget);

        // Appuyer sur "Voir avec chauffeur" bascule le SegmentedToggle sur "Avec chauffeur"
        await tester.ensureVisible(find.text('Voir avec chauffeur'));
        await tester.tap(find.text('Voir avec chauffeur'));
        await tester.pumpAndSettle();

        expect(find.text('non disponible sans chauffeur'), findsNothing);
        expect(find.textContaining('35'), findsWidgets);
        expect(find.textContaining('65'), findsWidgets);
        expect(find.text('Réserver'), findsNWidgets(2));
      },
    );

    testWidgets(
      'Demande de location : conditions permis/âge/caution affichées seulement sans chauffeur, estimation et envoi',
      (tester) async {
        final api = _Phase5FakeApi();
        const vehicle = Vehicle(
          id: 1,
          name: 'Toyota Corolla TEST',
          category: 'Berline',
          capacity: 5,
          state: 'AVAILABLE',
          description: 'Climatisée',
          dailyRate: 25000,
          dailyRateWithDriver: 35000,
          driverAvailable: true,
          baseLocation: Place(id: 1, name: 'Cotonou', address: ''),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: const RentalDetailScreen(
                vehicle: vehicle,
                initialWithDriver: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sans chauffeur : permis/âge et caution sont affichés
        expect(
          find.text(
            'Permis valide depuis au moins 2 ans, conducteur de 23 ans minimum',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Caution remboursable (montant communiqué par l’agence)'),
          findsOneWidget,
        );
        expect(
          find.text('Carburant à votre charge (rendu au même niveau)'),
          findsOneWidget,
        );
        // Estimation sur 2 jours : 2 × 25 000 = 50 000 FCFA
        expect(find.text('Estimation · 2 jours'), findsOneWidget);
        expect(find.textContaining('50'), findsWidgets);

        // Basculer sur "Avec chauffeur" : permis/âge et caution disparaissent
        await tester.tap(find.text('Avec chauffeur'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Permis valide depuis au moins 2 ans, conducteur de 23 ans minimum',
          ),
          findsNothing,
        );
        expect(
          find.text('Caution remboursable (montant communiqué par l’agence)'),
          findsNothing,
        );
        // Estimation sur 2 jours avec chauffeur : 2 × 35 000 = 70 000 FCFA
        expect(find.textContaining('70'), findsWidgets);

        // Mention aucun paiement dans l'app
        expect(
          find.textContaining('Aucun paiement maintenant'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Liste de véhicules vide affiche EmptyState "Bientôt disponible"',
      (tester) async {
        final api = _Phase5FakeApi(vehicles: const []);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: const RentalsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bientôt disponible'), findsOneWidget);
      },
    );
  });

  group('Phase 5 — Suivi de colis (ColisSuiviPhotos.html)', () {
    testWidgets(
      'Recherche par code affiche le statut et la frise TimelineSteps alimentée par l’historique du colis',
      (tester) async {
        final api = _Phase5FakeApi();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: const ParcelsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // État initial avant recherche
        expect(find.text('Suivez votre colis'), findsOneWidget);

        // Saisie du code et recherche
        await tester.enterText(
          find.byKey(const Key('parcel-tracking-input')),
          'AX-COL-TEST',
        );
        await tester.tap(find.byKey(const Key('parcel-track-button')));
        await tester.pumpAndSettle();

        expect(api.lastTrackedCode, 'AX-COL-TEST');
        expect(find.text('Cotonou → Parakou'), findsOneWidget);
        expect(find.byType(TimelineSteps), findsOneWidget);
        expect(find.text('Déposé à l’agence de Cotonou'), findsOneWidget);
        expect(find.text('En route vers Parakou'), findsWidgets);
        expect(find.text('Arrivé à l’agence de Parakou'), findsOneWidget);
        expect(find.text('Remis au destinataire'), findsOneWidget);
      },
    );

    testWidgets(
      'Galerie de 1 à 3 photos (UI pure) : affichage et agrandissement au toucher',
      (tester) async {
        final trackingWithPhotos = ParcelTracking(
          trackingNumber: 'AX-COL-PHOTOS-TEST',
          origin: 'Cotonou',
          destination: 'Parakou',
          photos: const [
            'photo_test_1',
            'photo_test_2',
            'photo_test_3',
          ],
          steps: const [
            ParcelStep(
              label: 'Déposé à l’agence de Cotonou',
              done: true,
              current: true,
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_Phase5FakeApi()),
            ],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: ParcelsScreen(initialTracking: trackingWithPhotos),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Photos prises au dépôt'), findsOneWidget);
        expect(find.text('3 / 3 · toucher pour agrandir'), findsOneWidget);
        expect(find.byKey(const Key('parcel-photo-thumb-0')), findsOneWidget);
        expect(find.byKey(const Key('parcel-photo-thumb-1')), findsOneWidget);
        expect(find.byKey(const Key('parcel-photo-thumb-2')), findsOneWidget);

        // Toucher la première miniature ouvre la boîte modale d'agrandissement
        await tester.tap(find.byKey(const Key('parcel-photo-thumb-0')));
        await tester.pumpAndSettle();

        expect(find.text('Photo 1 / 3'), findsOneWidget);
        expect(
          find.text('Photo prise au dépôt en agence Axis'),
          findsOneWidget,
        );

        // Fermer la boîte modale
        await tester.tap(find.byKey(const Key('parcel-photo-close')));
        await tester.pumpAndSettle();
        expect(find.text('Photo 1 / 3'), findsNothing);
      },
    );

    testWidgets(
      'Navigation client : les onglets Location et Colis sont présents et ouvrent leurs écrans',
      (tester) async {
        axisRouter.go('/');
        final api = _Phase5FakeApi();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: const AxisTransportApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Location'), findsOneWidget);
        expect(find.text('Colis'), findsOneWidget);

        // Ouvrir l'onglet Location
        await tester.tap(find.text('Location'));
        await tester.pumpAndSettle();
        expect(find.text('Location de véhicules'), findsOneWidget);

        // Ouvrir l'onglet Colis
        await tester.tap(find.text('Colis'));
        await tester.pumpAndSettle();
        expect(find.text('Suivi de colis'), findsOneWidget);
      },
    );
  });
}
