import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/formatters.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/axis_button.dart';
import 'package:axis_transport_flutter/core/widgets/photo_slots.dart';
import 'package:axis_transport_flutter/core/widgets/qr_scan_frame.dart';
import 'package:axis_transport_flutter/core/widgets/route_stops_bar.dart';
import 'package:axis_transport_flutter/features/sales/sell_ticket_screen.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_parcel_screen.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_scanner_screen.dart';
import 'package:axis_transport_flutter/features/staff/presentation/staff_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_audit.dart';
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
}

class _Phase6Api extends ApiClient {
  _Phase6Api() : super(store: _TestStore());

  Object? scanError;
  Map<String, dynamic>? scanSuccess;

  @override
  Future<User> me() async => const User(
    id: 11,
    username: 'raoul.test',
    firstName: 'Raoul',
    lastName: 'Test',
    phone: '+22901000000',
    role: 'CONTROLLER',
  );

  @override
  Future<List<Place>> locations() async => const [
    Place(id: 1, name: 'Bohicon', address: 'Gare Bohicon'),
    Place(id: 2, name: 'Dassa', address: 'Carrefour Dassa'),
    Place(id: 3, name: 'Parakou', address: 'Gare Parakou'),
  ];

  @override
  Future<Map<String, dynamic>> saleOptions() async => {
    'trips': [
      {
        'id': 7,
        'route_detail': {'label': 'Cotonou → Parakou'},
        'departure_at': '2026-10-12T07:00:00Z',
        'boarding_at': '2026-10-12T06:30:00Z',
        'available_seats': 4,
        'quotes': [
          {
            'payment_method': 1,
            'code': 'CASH',
            'label': 'Espèces',
            'amount': 1000,
            'fee_amount': 0,
            'total': 1000,
            'currency': 'XOF',
            'online': false,
          },
          {
            'payment_method': 2,
            'code': 'FEDAPAY',
            'label': 'FedaPay',
            'amount': 1000,
            'fee_amount': 18,
            'total': 1018,
            'currency': 'XOF',
            'online': true,
          },
        ],
      },
    ],
  };

  @override
  Future<List<Seat>> seats(int tripId) async => const [
    Seat(id: 21, number: '12', status: 'AVAILABLE'),
    Seat(id: 22, number: '15', status: 'PAID'),
  ];

  @override
  Future<Map<String, dynamic>> validateTicket(
    String qrToken, {
    int? expectedTripId,
  }) async {
    if (scanError != null) {
      throw scanError!;
    }
    return scanSuccess ??
        {
          'status': 'SUCCESS',
          'message': 'Billet validé avec succès.',
          'ticket': {
            'reference': qrToken,
            'passenger_name': 'Amina Boni TEST',
            'seat_detail': {'number': '12'},
            'trip_detail': {
              'route_detail': {'label': 'Cotonou → Parakou'},
            },
            'boarding_point_detail': {'name': 'Gare Jonquet'},
            'alighting_point_detail': {'name': 'Gare centrale Parakou'},
          },
        };
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('Audit des largeurs (320, 360, 390 ; texte 1,0 et 1,3)', () {
    Widget app(Widget home) => ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(_Phase6Api())],
          child: MaterialApp(theme: AxisTheme.light(), home: home),
        );
    final screens = <String, Widget Function()>{
      'accueil du personnel': () => app(StaffHomeScreen(stops: const [
            RouteStopItem(name: 'Cotonou', state: RouteStopState.passed),
            RouteStopItem(name: 'Bohicon', state: RouteStopState.current),
            RouteStopItem(name: 'Parakou', state: RouteStopState.upcoming),
          ])),
      'scanner': () => app(const ControllerScannerScreen(enableCamera: false)),
      'vente (contrôleur)': () => containerWithRole(api: _Phase6Api(), role: 'CONTROLLER', child: const SellTicketScreen()),
      'vente (guichet)': () => containerWithRole(api: _Phase6Api(), role: 'COUNTER', child: const SellTicketScreen()),
      'enregistrer un colis': () => app(const ControllerParcelScreen(fareFcfa: 2500)),
    };
    for (final entry in screens.entries) {
      testWidgets('${entry.key} : aucun débordement', (tester) async {
        expect(await layoutOverflows(tester, entry.value), isEmpty);
      });
    }
  });

  group('Phase 6 — Espace Contrôleur', () {
    testWidgets(
      'Accueil contrôleur (CtrlAccueil.html) : badge, trajet en cours + RouteStopsBar, tuiles et Ma journée',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final api = _Phase6Api();
        var arrivalConfirmed = false;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: StaffHomeScreen(
                stops: const [
                  RouteStopItem(name: 'Cotonou', state: RouteStopState.passed),
                  RouteStopItem(name: 'Bohicon', state: RouteStopState.current),
                  RouteStopItem(
                    name: 'Parakou',
                    state: RouteStopState.upcoming,
                  ),
                ],
                nextStopName: 'Bohicon',
                onConfirmArrival: () => arrivalConfirmed = true,
                daySummary: const ControllerDaySummary(
                  scannedTickets: 31,
                  soldTickets: 3,
                  parcelsCount: 2,
                  cashAmountFcfa: 22500,
                  mobileMoneyAmountFcfa: 15000,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CONTRÔLEUR'), findsOneWidget);
        expect(find.byType(RouteStopsBar), findsOneWidget);
        expect(find.text('Confirmer l’arrivée à Bohicon'), findsOneWidget);
        expect(find.text('Scanner un billet'), findsOneWidget);
        expect(find.text('Vendre un billet'), findsOneWidget);
        expect(find.text('Enregistrer un colis'), findsOneWidget);
        expect(find.text('31'), findsOneWidget);
        expect(find.text(formatMoney(22500, 'FCFA')), findsOneWidget);
        expect(find.text(formatMoney(15000, 'FCFA')), findsOneWidget);

        await tester.tap(find.text('Confirmer l’arrivée à Bohicon'));
        await tester.pump();
        expect(arrivalConfirmed, isTrue);
      },
    );

    testWidgets(
      'Scanner (Scanner.html) : QrScanFrame, saisie manuelle et 3 états ScanResultSheet + erreur réseau',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final api = _Phase6Api();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: const ControllerScannerScreen(enableCamera: false),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(QrScanFrame), findsOneWidget);
        expect(find.text('Saisir le code à la main'), findsOneWidget);

        // 1. État VALIDE
        await tester.tap(find.text('Saisir le code à la main'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'AX-2026-8829');
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        expect(find.text('Billet valide'), findsOneWidget);
        expect(find.text('Amina Boni TEST'), findsOneWidget);
        expect(find.text('Valider l’embarquement'), findsOneWidget);

        await tester.tap(find.text('Valider l’embarquement'));
        await tester.pumpAndSettle();

        // 2. État DÉJÀ UTILISÉ
        api.scanError = ApiException(
          'Ce ticket a déjà été contrôlé.',
          statusCode: 400,
          data: {'result': 'ALREADY_USED'},
        );
        await tester.tap(find.text('Saisir le code à la main'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'AX-2026-8804');
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        expect(find.text('Billet déjà utilisé'), findsOneWidget);
        expect(find.text('Scanner un autre billet'), findsOneWidget);
        await tester.tap(find.text('Scanner un autre billet'));
        await tester.pumpAndSettle();

        // 3. État INTROUVABLE
        api.scanError = ApiException('Ticket introuvable.', statusCode: 400);
        await tester.tap(find.text('Saisir le code à la main'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'AX-2026-0099');
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        expect(find.text('Billet introuvable'), findsOneWidget);
        expect(find.text('Vendre un billet à ce passager'), findsOneWidget);

        // 4. Erreur réseau hors connexion (sans logique hors ligne inventée)
        api.scanError = ApiException('Réseau indisponible.');
        await tester.tap(find.text('Saisir le code à la main'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'AX-2026-NET');
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Hors connexion : impossible de vérifier'),
          findsOneWidget,
        );
        expect(find.text('Réessayer'), findsOneWidget);
      },
    );

    testWidgets(
      'Vendre un billet (Vente.html) : SegmentedToggle Espèces / Mobile Money et libellé du bouton',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final api = _Phase6Api();
        await tester.pumpWidget(
          containerWithRole(
            api: api,
            role: 'CONTROLLER',
            child: const SellTicketScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('CONTRÔLEUR'), findsOneWidget);
        expect(find.text('Vendre un billet'), findsOneWidget);
        expect(find.text('Espèces'), findsOneWidget);
        expect(find.text('Mobile Money'), findsOneWidget);
        // Aucun nom de prestataire (FedaPay) affiché dans l'UI
        expect(find.text('FedaPay'), findsNothing);

        // Mode par défaut : Espèces -> "Encaisser 1 000 FCFA"
        expect(
          find.text('Encaisser ${formatMoney(1000, 'FCFA')}'),
          findsOneWidget,
        );

        // Bascule sur Mobile Money -> "Demander le paiement de 1 000 FCFA"
        await tester.tap(find.text('Mobile Money'));
        await tester.pumpAndSettle();
        expect(
          find.text('Demander le paiement de ${formatMoney(1000, 'FCFA')}'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Enregistrer un colis (CtrlColis.html) : PhotoSlots min 1 / max 3, bouton désactivé sans photo, compression 1280px JPEG 70',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final api = _Phase6Api();
        ParcelPhotoCaptureSettings? usedSettings;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [apiClientProvider.overrideWithValue(api)],
            child: MaterialApp(
              theme: AxisTheme.light(),
              home: ControllerParcelScreen(
                fareFcfa: 2500,
                onCapturePhoto: (settings) async {
                  usedSettings = settings;
                  return const PhotoSlotItem(
                    id: 'photo-test-1',
                    label: 'Photo TEST',
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Nouveau colis'), findsOneWidget);
        expect(find.text('0 / 3'), findsOneWidget);
        expect(
          find.text('Ajoutez au moins une photo pour enregistrer.'),
          findsOneWidget,
        );

        // Sans photo, le bouton de soumission est désactivé
        final submitBtnBefore = tester.widget<AxisButton>(
          find.byKey(const Key('parcel-submit')),
        );
        expect(submitBtnBefore.onPressed, isNull);

        // Ajout d'une première photo
        await tester.tap(find.text('Photo'));
        await tester.pumpAndSettle();

        expect(usedSettings?.maxWidthPx, 1280);
        expect(usedSettings?.jpegQuality, 70);
        expect(find.text('1 / 3'), findsOneWidget);
        expect(
          find.text('Ajoutez au moins une photo pour enregistrer.'),
          findsNothing,
        );

        // Avec 1 photo, le bouton est activé
        final submitBtnAfter = tester.widget<AxisButton>(
          find.byKey(const Key('parcel-submit')),
        );
        expect(submitBtnAfter.onPressed, isNotNull);
        expect(
          find.text('Enregistrer le colis'),
          findsOneWidget,
        );
        expect(find.text(formatMoney(2500, 'FCFA')), findsOneWidget);
      },
    );
  });
}

Widget containerWithRole({
  required ApiClient api,
  required String role,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: AxisTheme.light(),
      home: _SessionInitializer(child: child),
    ),
  );
}

class _SessionInitializer extends ConsumerStatefulWidget {
  const _SessionInitializer({required this.child});
  final Widget child;

  @override
  ConsumerState<_SessionInitializer> createState() =>
      _SessionInitializerState();
}

class _SessionInitializerState extends ConsumerState<_SessionInitializer> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sessionProvider.notifier).restore());
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(sessionProvider).ready;
    if (!ready) return const SizedBox.shrink();
    return widget.child;
  }
}
