import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/photo_slots.dart';
import 'package:axis_transport_flutter/features/staff/presentation/controller_parcel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Colis du contrôleur : après l'enregistrement, l'encaissement passe par `/parcels/{id}/pay/`.
class _PayApi extends ApiClient {
  _PayApi({this.methods = const [], this.payError, this.checkoutUrl});
  final List<PaymentMethod> methods;
  final String? payError;
  final String? checkoutUrl;
  final paid = <List<int>>[];
  int verified = 0;

  @override
  Future<Map<String, dynamic>> saleOptions() async => {
    'parcel_base_fcfa': 2000,
    'trips': [
      {
        'id': 9,
        'route_detail': {
          'label': 'Parakou → Cotonou',
          'stops': [
            {'id': 1, 'name': 'Parakou', 'position': 1},
            {'id': 4, 'name': 'Cotonou', 'position': 2},
          ],
        },
        'arrivals': [],
        'departure_at': '2026-11-05T07:00:00Z',
        'available_seats': 40,
        'quotes': [],
      },
    ],
  };

  @override
  Future<List<Place>> locations() async => const [];

  @override
  Future<Map<String, dynamic>> createParcel(
    Map<String, dynamic> fields,
    List<List<int>> photos,
  ) async => {'id': 77, 'tracking_number': 'TEST-COLIS-2', 'amount': 2000};

  @override
  Future<List<PaymentMethod>> paymentMethods() async => methods;

  @override
  Future<Map<String, dynamic>> payParcel(
    int parcelId,
    int paymentMethodId,
  ) async {
    if (payError != null) throw ApiException(payError!);
    paid.add([parcelId, paymentMethodId]);
    return {
      'checkout': checkoutUrl == null ? null : {'payment_url': checkoutUrl},
    };
  }

  @override
  Future<Map<String, dynamic>> verifyParcelPayment(int parcelId) async {
    verified++;
    return {'receipt': {}};
  }
}

const _cash = PaymentMethod(
  id: 1,
  code: 'especes',
  label: 'Espèces',
  active: true,
);
const _momo = PaymentMethod(
  id: 2,
  code: 'FEDAPAY',
  label: 'Mobile Money',
  active: true,
  online: true,
);

Future<void> _registerParcel(
  WidgetTester tester,
  _PayApi api, {
  bool mobileMoney = false,
}) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: AxisTheme.light(),
        home: ControllerParcelScreen(
          openPayment: (_) async => false,
          onCapturePhoto: (_) async =>
              const PhotoSlotItem(id: 'p1', label: 'Photo TEST'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Photo'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  for (var index = 0; index < 4; index++) {
    await tester.enterText(
      fields.at(index),
      index.isEven ? 'TEST Nom' : '90000000',
    );
  }
  await tester.enterText(fields.at(4), 'TEST carton');
  if (mobileMoney) {
    await tester.ensureVisible(find.text('Mobile Money'));
    await tester.tap(find.text('Mobile Money'));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(const Key('parcel-submit')));
  await tester.tap(find.byKey(const Key('parcel-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Enregistrer'));
  for (
    var step = 0;
    step < 30 && find.byKey(const Key('parcel-pay')).evaluate().isEmpty;
    step++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  expect(find.byKey(const Key('parcel-pay')), findsOneWidget);
}

void main() {
  setUpAll(() async => initializeDateFormatting('fr_FR'));

  testWidgets('Espèces : confirmation, puis colis payé', (tester) async {
    final api = _PayApi(methods: const [_cash, _momo]);
    await _registerParcel(tester, api);
    expect(find.text('Encaisser 2000 FCFA en espèces'), findsOneWidget);
    await tester.tap(find.byKey(const Key('parcel-pay')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oui, reçues'));
    await tester.pumpAndSettle();
    expect(api.paid, [
      [77, 1],
    ]);
    expect(find.byKey(const Key('parcel-paid')), findsOneWidget);
  });

  testWidgets(
    'Mobile Money : la demande part, puis « Vérifier le paiement » confirme',
    (tester) async {
      final api = _PayApi(
        methods: const [_cash, _momo],
        checkoutUrl: 'https://paiement.test/TEST',
      );
      await _registerParcel(tester, api, mobileMoney: true);
      await tester.tap(find.byKey(const Key('parcel-pay')));
      await tester.pumpAndSettle();
      expect(api.paid, [
        [77, 2],
      ]);
      // Sans navigateur dans les tests, la page ne s'ouvre pas : le message le dit, la vérification reste possible.
      expect(find.byKey(const Key('parcel-verify')), findsOneWidget);
      await tester.tap(find.byKey(const Key('parcel-verify')));
      await tester.pumpAndSettle();
      expect(api.verified, 1);
      expect(find.byKey(const Key('parcel-paid')), findsOneWidget);
    },
  );

  testWidgets('Mobile Money non activé : message lisible, aucun appel', (
    tester,
  ) async {
    final api = _PayApi(methods: const [_cash]);
    await _registerParcel(tester, api, mobileMoney: true);
    await tester.tap(find.byKey(const Key('parcel-pay')));
    await tester.pumpAndSettle();
    expect(api.paid, isEmpty);
    expect(
      find.textContaining('Mobile Money n’est pas activé'),
      findsOneWidget,
    );
  });

  testWidgets('Refus du serveur : son message s’affiche', (tester) async {
    final api = _PayApi(
      methods: const [_cash, _momo],
      payError:
          'Le paiement Mobile Money n\'est pas disponible pour le moment.',
    );
    await _registerParcel(tester, api, mobileMoney: true);
    await tester.tap(find.byKey(const Key('parcel-pay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parcel-pay-error')), findsOneWidget);
    expect(
      find.textContaining('pas disponible pour le moment'),
      findsOneWidget,
    );
  });
}
