import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_draft.dart';
import 'package:axis_transport_flutter/features/passengers/domain/passenger.dart';
import 'package:axis_transport_flutter/features/passengers/presentation/passengers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MemStore extends SessionStore {
  @override
  Future<void> setActiveClient(int userId) async {}
}

const _p = BoardingPointInfo.new;

/// Parakou : 2 points (TEST) ; Savè : aucun ; Cotonou : 1 point (TEST).
final _trip = Trip(
  id: 10,
  route: RouteInfo(
    id: 1,
    label: 'Parakou → Cotonou',
    origin: Place(
      id: 1,
      name: 'Parakou',
      address: '',
      boardingPoints: [
        _p(id: 11, name: 'TEST Gare A'),
        _p(id: 12, name: 'TEST Gare B'),
      ],
    ),
    destination: Place(
      id: 2,
      name: 'Cotonou',
      address: '',
      boardingPoints: [_p(id: 21, name: 'TEST Arrêt Cotonou')],
    ),
    stops: [
      RouteStopInfo(
        id: 1,
        name: 'Parakou',
        position: 1,
        boardingPoints: [
          _p(id: 11, name: 'TEST Gare A'),
          _p(id: 12, name: 'TEST Gare B'),
        ],
      ),
      const RouteStopInfo(id: 3, name: 'Savè', position: 2),
      RouteStopInfo(
        id: 2,
        name: 'Cotonou',
        position: 3,
        boardingPoints: [_p(id: 21, name: 'TEST Arrêt Cotonou')],
      ),
    ],
  ),
  departureAt: DateTime(2026, 10, 30, 8, 0),
  status: 'SCHEDULED',
  statusDisplay: 'Programmé',
  note: '',
  availableSeats: 23,
  currentFare: const Fare(id: 1, name: 'TEST', amount: 7500, currency: 'XOF'),
);

class _Api extends ApiClient {
  _Api() : super(store: _MemStore());

  @override
  Future<Trip> trip(int tripId, {int? originId, int? destinationId}) async =>
      _trip;

  @override
  Future<User> me() async => const User(
    id: 1,
    username: 'test',
    firstName: 'TEST',
    lastName: 'Client',
    phone: '+22900000000',
    role: 'CLIENT',
  );
}

Future<ProviderContainer> _open(
  WidgetTester tester, {
  int? passengers,
  int? originId,
  int? destinationId,
  ProviderContainer? container,
}) async {
  final c =
      container ??
      ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(_Api())],
      );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AxisTheme.light(),
        home: PassengersScreen(
          tripId: 10,
          passengerCount: passengers,
          originId: originId,
          destinationId: destinationId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('aucune erreur de point affichée à l’ouverture', (tester) async {
    await _open(tester, originId: 1, destinationId: 2);
    expect(find.textContaining('Veuillez choisir'), findsNothing);
  });

  testWidgets('libellés : « Où montez-vous » et « Où descendez-vous »', (
    tester,
  ) async {
    await _open(tester, originId: 1, destinationId: 2);
    expect(find.text('Où montez-vous à Parakou ?'), findsOneWidget);
    expect(find.text('Où descendez-vous à Cotonou ?'), findsOneWidget);
    expect(find.text('Choisissez l’arrêt exact'), findsWidgets);
  });

  testWidgets('un seul point : pas de liste, son nom est affiché et retenu', (
    tester,
  ) async {
    final c = await _open(tester, originId: 1, destinationId: 2);
    // Une seule liste (Parakou, 2 points) ; Cotonou est affiché en texte.
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('TEST Arrêt Cotonou'), findsOneWidget);
    expect(c.read(bookingDraftProvider).alightingPointId, 21);
  });

  testWidgets('plusieurs points : aucune présélection, choix obligatoire', (
    tester,
  ) async {
    final c = await _open(tester, originId: 1, destinationId: 2);
    expect(c.read(bookingDraftProvider).boardingPointId, isNull);
    await tester.scrollUntilVisible(
      find.text('Continuer vers les sièges'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continuer vers les sièges'));
    await tester.pumpAndSettle();
    expect(
      find.text('Veuillez choisir un point d\'embarquement.'),
      findsOneWidget,
    );
    expect(find.textContaining('point de débarquement'), findsNothing);
  });

  testWidgets(
    'arrêt intermédiaire sans point : aucun point d’une autre ville',
    (tester) async {
      final c = await _open(tester, originId: 3, destinationId: 2);
      // Aucune liste : Savè n'a pas de point, Cotonou n'en a qu'un.
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.textContaining('Où montez-vous'), findsNothing);
      expect(c.read(bookingDraftProvider).boardingPointId, isNull);
    },
  );

  testWidgets('le nombre de passagers de la recherche prime sur le brouillon', (
    tester,
  ) async {
    final c = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(_Api())],
    );
    c.read(bookingDraftProvider.notifier).start(_trip);
    c.read(bookingDraftProvider.notifier).setPassengers(const [
      Passenger(
        id: 'passenger-1',
        fullName: 'TEST Un',
        phone: '',
        type: PassengerType.adult,
      ),
    ]);
    await _open(
      tester,
      passengers: 3,
      originId: 1,
      destinationId: 2,
      container: c,
    );
    expect(find.text('3 passagers'), findsOneWidget);
  });

  testWidgets('ajouter ou retirer un passager met à jour le brouillon', (
    tester,
  ) async {
    final c = await _open(tester, passengers: 2, originId: 1, destinationId: 2);
    expect(c.read(bookingDraftProvider).passengers.length, 2);
    await tester.scrollUntilVisible(
      find.text('Ajouter un passager'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ajouter un passager'));
    await tester.pump();
    expect(c.read(bookingDraftProvider).passengers.length, 3);
    await tester.tap(find.byTooltip('Supprimer ce passager').first);
    await tester.pump();
    expect(c.read(bookingDraftProvider).passengers.length, 2);
  });
}
