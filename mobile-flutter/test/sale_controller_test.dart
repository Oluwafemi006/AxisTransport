import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/formatters.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/session_store.dart';
import 'package:axis_transport_flutter/features/sales/sale_controller.dart';
import 'package:axis_transport_flutter/features/sales/sale_models.dart';
import 'package:axis_transport_flutter/features/sales/sell_ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Store extends SessionStore {}

Map<String, dynamic> _quote(
  int id,
  String label,
  num total, {
  bool online = false,
}) => {
  'payment_method': id,
  'code': label.toUpperCase(),
  'label': label,
  'amount': 1000,
  'fee_amount': total - 1000,
  'total': total,
  'currency': 'XOF',
  'online': online,
};

Map<String, dynamic> _trip({List<Map<String, dynamic>>? quotes}) => {
  'id': 7,
  'route_detail': {'label': 'Cotonou → Parakou'},
  'departure_at': '2026-10-12T07:00:00Z',
  'boarding_at': '2026-10-12T06:30:00Z',
  'available_seats': 3,
  'quotes':
      quotes ??
      [_quote(1, 'Espèces', 1000), _quote(2, 'FedaPay', 1018, online: true)],
};

Map<String, dynamic> _booking(String status, {String ticketStatus = 'HELD'}) =>
    {
      'id': 90,
      'status': status,
      'reservation_expires_at': DateTime.now()
          .add(const Duration(minutes: 10))
          .toUtc()
          .toIso8601String(),
      'tickets': [
        {
          'reference': 'AX-20261012-ABCDEF12',
          'status': ticketStatus,
          'status_display': ticketStatus == 'ISSUED'
              ? 'Ticket émis'
              : 'Réservé temporairement',
          'passenger_name': 'Awa Test',
          'seat_detail': {'number': '2A'},
          'trip_detail': {
            'route_detail': {'label': 'Cotonou → Parakou'},
            'departure_at': '2026-10-12T07:00:00Z',
            'boarding_at': '2026-10-12T06:30:00Z',
          },
          'amount': '1000.00',
          'currency': 'XOF',
          'public_url': '',
        },
      ],
    };

/// Faux serveur : compte les appels et retient les clés reçues.
/// (Repris de l'app staff ; une erreur sans code HTTP représente une coupure réseau.)
class _Api extends ApiClient {
  _Api() : super(store: _Store());

  List<Map<String, dynamic>> tripList = [_trip()];
  final keys = <String>[];
  int sells = 0, verifies = 0, cancels = 0;
  Object? sellError;
  Object? verifyError;
  String? paymentError;

  @override
  Future<Map<String, dynamic>> saleOptions() async => {'trips': tripList};

  @override
  Future<List<Seat>> seats(int tripId) async => const [
    Seat(id: 21, number: '2A', status: 'AVAILABLE'),
    Seat(id: 22, number: '2B', status: 'PAID'),
  ];

  @override
  Future<Map<String, dynamic>> sellTicket({
    required String idempotencyKey,
    required int trip,
    required int seat,
    required String passengerName,
    required String passengerPhone,
    required int paymentMethod,
    String? origin,
    String? destination,
    int? boardingPointId,
    int? alightingPointId,
  }) async {
    sells += 1;
    keys.add(idempotencyKey);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (sellError != null) {
      throw sellError!;
    }
    if (paymentMethod == 1) {
      return {
        'booking': _booking('CONFIRMED', ticketStatus: 'ISSUED'),
        'checkout': null,
      };
    }
    if (paymentError != null) {
      return {
        'booking': _booking('HELD'),
        'checkout': null,
        'payment_error': paymentError,
      };
    }
    return {
      'booking': _booking('HELD'),
      'checkout': {
        'transaction_id': 5001,
        'payment_url': 'https://paiement.exemple.test/x',
        'payment_method': 2,
        'total': 1018,
        'currency': 'XOF',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> verifySale({
    required int bookingId,
    required int paymentMethod,
    required String externalReference,
  }) async {
    verifies += 1;
    if (verifyError != null) throw verifyError!;
    return {'booking': _booking('CONFIRMED', ticketStatus: 'ISSUED')};
  }

  @override
  Future<Map<String, dynamic>> cancelSale(int bookingId) async {
    cancels += 1;
    return {
      'booking': _booking('CANCELLED', ticketStatus: 'CANCELLED'),
      'cancelled': true,
    };
  }
}

Future<(SaleController, _Api)> _ready({bool online = false}) async {
  final api = _Api();
  final controller = SaleController(api);
  await controller.load();
  await controller.selectTrip(controller.trips.single);
  controller.selectSeat(controller.seats.first);
  controller.selectQuote(controller.trip!.quotes[online ? 1 : 0]);
  return (controller, api);
}

Future<void> _sell(SaleController controller) =>
    controller.sell(passengerName: 'Awa Test', passengerPhone: '90000000');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('les départs, places et montants viennent du serveur', () async {
    final (controller, _) = await _ready();
    expect(controller.trips.single.availableSeats, 3);
    expect(controller.trip!.quotes.map((item) => item.total), [1000, 1018]);
    expect(controller.seats.where((item) => item.isAvailable).length, 1);
    expect(controller.canSell, isTrue);
  });

  test('sans tarif en base, le départ n’est pas vendable', () async {
    final api = _Api()..tripList = [_trip(quotes: [])];
    final controller = SaleController(api);
    await controller.load();
    await controller.selectTrip(controller.trips.single);
    controller.selectSeat(controller.seats.first);
    expect(controller.trip!.hasFare, isFalse);
    expect(controller.canSell, isFalse);
    await _sell(controller);
    expect(api.sells, 0);
  });

  test('vente contrôleur refusée pour tarif manquant : message clair, saisie gardée', () async {
    final (controller, api) = await _ready();
    api.sellError = ApiException(
      segmentFareMissingMessage,
      statusCode: 400,
      data: const {'code': segmentFareMissingCode},
    );
    await _sell(controller);
    expect(controller.error, segmentFareMissingMessage);
    expect(controller.sale, isNull);
    expect(controller.trip, isNotNull);
    expect(controller.seat, isNotNull);
  });

  test('vente en espèces : le billet est émis par le serveur', () async {
    final (controller, api) = await _ready();
    await _sell(controller);
    expect(api.sells, 1);
    expect(controller.sale!.isIssued, isTrue);
    expect(controller.sale!.ticket!.reference, 'AX-20261012-ABCDEF12');
    expect(controller.error, isNull);
  });

  test('un double appui n’envoie qu’une vente', () async {
    final (controller, api) = await _ready();
    await Future.wait([_sell(controller), _sell(controller)]);
    expect(api.sells, 1);
  });

  test('coupure réseau : aucun billet annoncé, et le nouvel essai reprend la même vente', () async {
    final (controller, api) = await _ready();
    api.sellError = ApiException('Réseau indisponible.');
    await _sell(controller);
    expect(controller.sale, isNull);
    expect(controller.error, contains('Aucun billet n\'est confirmé'));
    expect(controller.saleKey, isNotNull);

    api.sellError = null;
    await _sell(controller);
    expect(controller.sale!.isIssued, isTrue);
    // Même clé aux deux envois : le serveur ne peut pas créer deux ventes.
    expect(api.keys.toSet().length, 1);
  });

  test('refus du serveur avant toute réservation : la vente suivante repart avec une nouvelle clé', () async {
    final (controller, api) = await _ready();
    api.sellError = ApiException(
      'Un ou plusieurs sièges ne sont plus disponibles.',
      statusCode: 400,
    );
    await _sell(controller);
    expect(controller.error, contains('plus disponibles'));
    expect(controller.sale, isNull);
    api.sellError = null;
    await _sell(controller);
    expect(api.keys.toSet().length, 2);
  });

  test('Mobile Money : place tenue, billet seulement après vérification par le serveur', () async {
    final (controller, api) = await _ready(online: true);
    await _sell(controller);
    expect(controller.sale!.isHeld, isTrue);
    expect(controller.sale!.isIssued, isFalse);
    expect(controller.checkout!.paymentUrl, isNotNull);
    expect(controller.checkout!.total, 1018);

    api.verifyError = ApiException(
      'Transaction non approuvée.',
      statusCode: 400,
      data: {'payment_status': 'pending'},
    );
    await controller.verify();
    expect(controller.sale!.isHeld, isTrue);
    expect(controller.error, contains('pas encore reçu'));

    api.verifyError = null;
    await controller.verify();
    expect(controller.sale!.isIssued, isTrue);
    expect(controller.checkout, isNull);
  });

  test(
    'paiement arrivé après expiration : aucun billet, remboursement signalé',
    () async {
      final (controller, api) = await _ready(online: true);
      await _sell(controller);
      api.verifyError = ApiException(
        'Paiement reçu après l\'expiration.',
        statusCode: 409,
        data: {'refund_due': true},
      );
      await controller.verify();
      expect(controller.refundDue, isTrue);
      expect(controller.sale!.isIssued, isFalse);
    },
  );

  test('le paiement ne démarre pas : la place reste tenue et le réessai garde la même vente', () async {
    final (controller, api) = await _ready(online: true);
    api.paymentError = 'Impossible de contacter FedaPay.';
    await _sell(controller);
    expect(controller.paymentFailed, isTrue);
    expect(controller.sale!.isHeld, isTrue);
    expect(controller.checkout, isNull);

    api.paymentError = null;
    await _sell(controller);
    expect(controller.checkout, isNotNull);
    expect(controller.paymentFailed, isFalse);
    expect(api.keys.toSet().length, 1);
  });

  test(
    'annulation : demandée au serveur, puis écran prêt pour une nouvelle vente',
    () async {
      final (controller, api) = await _ready(online: true);
      await _sell(controller);
      final firstKey = controller.saleKey;
      await controller.cancel();
      expect(api.cancels, 1);
      expect(controller.sale, isNull);
      expect(controller.saleKey, isNull);
      controller.selectSeat(controller.seats.first);
      await _sell(controller);
      expect(api.keys.last, isNot(firstKey));
    },
  );

  test('le texte de partage ne contient que des valeurs du serveur, et le lien seulement s’il existe', () {
    final ticket = SaleTicket.fromJson(
      (_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
    );
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text, contains('AX-20261012-ABCDEF12'));
    expect(text, contains('Awa Test'));
    expect(text, contains('Cotonou → Parakou'));
    expect(text, contains('Embarquement'));
    expect(text, isNot(contains('http')));

    final withLink = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List)
              .first
          as Map<String, dynamic>,
      'public_url': 'https://site.exemple.test/t/AX-20261012-ABCDEF12',
    });
    expect(
      saleShareText(withLink, formatFullDateTime),
      contains('https://site.exemple.test/t/AX-20261012-ABCDEF12'),
    );
  });

  test('le texte de partage inclut le prix en FCFA', () {
    final ticket = SaleTicket.fromJson(
      (_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
    );
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text.replaceAll(RegExp(r'\s'), ''), contains('Prixdubillet:1000FCFA'));
  });

  test('le texte de partage inclut l\'IFU de l\'acheteur seulement s\'il est renseigné', () {
    final withoutIfu = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'print_info': {
        'buyer_ifu': '',
      },
    });
    expect(saleShareText(withoutIfu, formatFullDateTime), isNot(contains("IFU de l'acheteur")));

    final withIfu = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'print_info': {
        'buyer_ifu': 'TEST-IFU-ACHETEUR',
      },
    });
    expect(
      saleShareText(withIfu, formatFullDateTime),
      contains('IFU de l\'acheteur : TEST-IFU-ACHETEUR'),
    );
  });

  test('le texte de partage ne contient jamais de ligne de TVA ni de mention HT/TTC, même si présentes dans print_info', () {
    final withoutTaxes = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'print_info': {
        'price_incl_tax': 1000,
        'price_excl_tax': null,
        'tax_lines': [],
      },
    });
    final textWithout = saleShareText(withoutTaxes, formatFullDateTime);
    expect(textWithout, isNot(contains('Prix HT')));
    expect(textWithout, isNot(contains('TVA')));
    expect(textWithout, isNot(contains('Prix TTC')));
    expect(textWithout, isNot(contains('XOF')));
    expect(textWithout, contains('FCFA'));

    final withTaxes = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'amount': 1000,
      'currency': 'XOF',
      'print_info': {
        'buyer_ifu': 'TEST-IFU-123',
        'price_incl_tax': 1000,
        'price_excl_tax': 847,
        'tax_lines': [
          {'name': 'TVA', 'rate': '18', 'amount': 153},
        ],
      },
    });
    final textWith = saleShareText(withTaxes, formatFullDateTime);
    expect(textWith, contains('IFU de l\'acheteur : TEST-IFU-123'));
    expect(textWith, isNot(contains('Prix HT')));
    expect(textWith, isNot(contains('TVA')));
    expect(textWith, isNot(contains('Prix TTC')));
    expect(textWith.replaceAll(RegExp(r'\s'), ''), contains('Prixdubillet:1000FCFA'));
    expect(textWith, isNot(contains('XOF')));
    expect(textWith, contains('FCFA'));
  });

  test('le texte de partage ignore un IFU composé uniquement d\'espaces', () {
    final ticket = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'print_info': {
        'buyer_ifu': '   ',
      },
    });
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text, isNot(contains("IFU de l'acheteur")));
  });

  test('le texte de partage gère un print_info nul sans erreur et sans XOF', () {
    final ticket = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'print_info': null,
    });
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text, contains('Billet : AX-20261012-ABCDEF12'));
    expect(text, contains('Passager : Awa Test'));
    expect(text, contains('Statut : Payé'));
    expect(text.replaceAll(RegExp(r'\s'), ''), contains('Prixdubillet:1000FCFA'));
    expect(text, isNot(contains('À renseigner')));
    expect(text, isNot(contains('XOF')));
    expect(text, contains('FCFA'));
  });

  test('le texte de partage inclut Statut Payé, Vendeur, Mode de paiement et bas de billet', () {
    final ticket = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'currency': 'XOF',
      'print_info': {
        'paid': true,
        'sale': 'Vendeur : Agent Test',
        'payment_mode': 'Espèces',
        'buyer_ifu': 'TEST-IFU-123',
        'agency': {
          'legal_name': 'AXIS Transport SARL',
          'ifu': 'TEST-IFU-0000',
          'rccm': 'TEST-RCCM-0000',
          'address': 'Cotonou, Bénin',
          'phones': '+229 01 02 03 04',
          'email': 'contact@axis.test',
        },
        'conditions': 'Billet non échangeable',
      },
    });
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text, contains('Statut : Payé'));
    expect(text, contains('Vendeur : Agent Test'));
    expect(text, contains('Mode de paiement : Espèces'));
    expect(text, contains('IFU de l\'acheteur : TEST-IFU-123'));
    expect(text, contains('Raison sociale : AXIS Transport SARL'));
    expect(text, contains('IFU : TEST-IFU-0000 · RCCM : TEST-RCCM-0000'));
    expect(text, contains('Adresse : Cotonou, Bénin'));
    expect(text, contains('Contacts : +229 01 02 03 04 · contact@axis.test'));
    expect(text, contains('Conditions : Billet non échangeable'));
    expect(text, isNot(contains('XOF')));
    expect(text, contains('FCFA'));
  });

  test('le texte de partage n\'affiche pas de lignes de TVA si la TVA est à zéro', () {
    final zeroTax = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'amount': 1000,
      'currency': 'XOF',
      'print_info': {
        'price_incl_tax': 1000,
        'price_excl_tax': 1000,
        'tax_lines': [
          {'name': 'TVA', 'rate': '0', 'amount': 0},
        ],
      },
    });
    final text = saleShareText(zeroTax, formatFullDateTime);
    expect(text, isNot(contains('TVA')));
    expect(text, isNot(contains('Prix HT')));
    expect(text, isNot(contains('Prix TTC')));
    expect(text.replaceAll(RegExp(r'\s'), ''), contains('Prixdubillet:1000FCFA'));
    expect(text, isNot(contains('XOF')));
    expect(text, contains('FCFA'));
  });

  test('aucune ligne de TVA ni de Prix TTC n\'apparaît si price_excl_tax est présent sans price_incl_tax', () {
    final ticket = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'amount': 1000,
      'currency': 'XOF',
      'print_info': {
        'price_excl_tax': 847,
        'tax_lines': [
          {'name': 'TVA', 'rate': '18', 'amount': 153},
        ],
      },
    });
    final text = saleShareText(ticket, formatFullDateTime);
    expect(text, isNot(contains('TVA')));
    expect(text, isNot(contains('Prix HT')));
    expect(text, isNot(contains('Prix TTC')));
    expect(text.replaceAll(RegExp(r'\s'), ''), contains('Prixdubillet:1000FCFA'));
    expect(text, isNot(contains('XOF')));
    expect(text, contains('FCFA'));
  });

  testWidgets('l\'écran de fin de vente affiche le récapitulatif sans XOF et avec mentions complètes', (tester) async {
    final ticket = SaleTicket.fromJson({
      ...(_booking('CONFIRMED', ticketStatus: 'ISSUED')['tickets'] as List).first
          as Map<String, dynamic>,
      'amount': 1000,
      'currency': 'XOF',
      'print_info': {
        'paid': true,
        'sale': 'Vendeur : Agent Test',
        'payment_mode': 'Espèces',
        'buyer_ifu': 'TEST-IFU-123',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SaleIssuedCard(ticket: ticket),
          ),
        ),
      ),
    );

    expect(find.text('Billet émis · AX-20261012-ABCDEF12'), findsOneWidget);
    expect(find.text('Passager : Awa Test'), findsOneWidget);
    expect(find.text('Siège : 2A'), findsOneWidget);
    expect(find.text('Trajet : Cotonou → Parakou'), findsOneWidget);
    expect(find.text('Prix du billet : ${formatMoney(ticket.amount, ticket.currency)}'), findsOneWidget);
    expect(find.text('Statut : Payé'), findsOneWidget);
    expect(find.text('Vendeur : Agent Test'), findsOneWidget);
    expect(find.text('Mode de paiement : Espèces'), findsOneWidget);
    expect(find.text('IFU de l\'acheteur : TEST-IFU-123'), findsOneWidget);
    expect(find.textContaining('FCFA'), findsWidgets);
    expect(find.textContaining('XOF'), findsNothing);
    expect(find.textContaining('TVA'), findsNothing);
    expect(find.textContaining('Prix HT'), findsNothing);
    expect(find.textContaining('Prix TTC'), findsNothing);
  });
}
