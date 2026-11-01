// Données de la vente par un agent, lues telles quelles dans les réponses du serveur.
// L'application ne calcule ni prix, ni frais, ni disponibilité.

import '../../core/formatters.dart';
import '../../core/models.dart';

num _num(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

/// Montant à encaisser pour un départ avec un moyen de paiement donné.
class SaleQuote {
  const SaleQuote({
    required this.paymentMethod,
    required this.label,
    required this.amount,
    required this.feeAmount,
    required this.total,
    required this.currency,
    required this.online,
  });

  final int paymentMethod;
  final String label;
  final num amount;
  final num feeAmount;
  final num total;
  final String currency;

  /// Vrai pour un paiement vérifié auprès d'un prestataire (Mobile Money) ; faux pour les espèces.
  final bool online;

  factory SaleQuote.fromJson(Map<String, dynamic> json) => SaleQuote(
    paymentMethod: json['payment_method'] as int,
    label: json['label'] as String? ?? '',
    amount: _num(json['amount']),
    feeAmount: _num(json['fee_amount']),
    total: _num(json['total']),
    currency: json['currency'] as String? ?? 'XOF',
    online: json['online'] == true,
  );
}

/// Départ vendable par l'agent connecté.
class SaleTrip {
  const SaleTrip({
    required this.id,
    required this.label,
    required this.departureAt,
    required this.boardingAt,
    required this.availableSeats,
    required this.quotes,
    this.originName = '',
    this.destinationName = '',
    this.originBoardingPoints = const [],
    this.destinationBoardingPoints = const [],
    this.originId,
    this.destinationId,
  });

  final int id;

  /// Tronçon vendu ; absents, c'est le parcours entier.
  final int? originId;
  final int? destinationId;

  /// Un même départ apparaît une fois par tronçon.
  String get key => '$id-$originId-$destinationId';
  final String label;
  final DateTime? departureAt;
  final DateTime? boardingAt;
  final int availableSeats;
  final String originName;
  final String destinationName;
  final List<BoardingPointInfo> originBoardingPoints;
  final List<BoardingPointInfo> destinationBoardingPoints;

  /// Vide quand aucun tarif n'est défini en base : le départ n'est alors pas vendable.
  final List<SaleQuote> quotes;

  bool get hasFare => quotes.isNotEmpty;

  /// Un choix par tronçon vendable du départ, tels que renvoyés par le serveur.
  static List<SaleTrip> choicesFromJson(Map<String, dynamic> json) {
    final segments = json['segments'] as List? ?? const [];
    final base = SaleTrip.fromJson(json);
    if (segments.isEmpty) return [base];
    final stops = _map(json['route_detail'])['stops'] as List? ?? const [];
    List<BoardingPointInfo> pointsOf(Object? stopId) {
      for (final stop in stops) {
        final row = _map(stop);
        if (row['id'] == stopId) {
          return (row['boarding_points'] as List? ?? const [])
              .map((item) => BoardingPointInfo.fromJson(_map(item)))
              .where((p) => p.active)
              .toList();
        }
      }
      return const [];
    }

    return [
      for (final item in segments)
        () {
          final row = _map(item);
          return SaleTrip(
            id: base.id,
            label: '${row['origin']} → ${row['destination']}',
            departureAt: base.departureAt,
            boardingAt: base.boardingAt,
            availableSeats: base.availableSeats,
            originName: row['origin'] as String? ?? '',
            destinationName: row['destination'] as String? ?? '',
            originId: row['origin_id'] as int?,
            destinationId: row['destination_id'] as int?,
            originBoardingPoints: pointsOf(row['origin_id']),
            destinationBoardingPoints: pointsOf(row['destination_id']),
            quotes: (row['quotes'] as List? ?? const [])
                .map((quote) => SaleQuote.fromJson(_map(quote)))
                .toList(),
          );
        }(),
    ];
  }

  factory SaleTrip.fromJson(Map<String, dynamic> json) {
    final routeDetail = _map(json['route_detail']);
    final originDetail = _map(routeDetail['origin_detail']);
    final destDetail = _map(routeDetail['destination_detail']);
    return SaleTrip(
      id: json['id'] as int,
      label: routeDetail['label'] as String? ?? '',
      departureAt: _date(json['departure_at']),
      boardingAt: _date(json['boarding_at']),
      availableSeats: json['available_seats'] as int? ?? 0,
      originName: originDetail['name'] as String? ?? '',
      destinationName: destDetail['name'] as String? ?? '',
      originBoardingPoints: (originDetail['boarding_points'] as List? ?? const [])
          .map((item) => BoardingPointInfo.fromJson(_map(item)))
          .where((p) => p.active)
          .toList(),
      destinationBoardingPoints: (destDetail['boarding_points'] as List? ?? const [])
          .map((item) => BoardingPointInfo.fromJson(_map(item)))
          .where((p) => p.active)
          .toList(),
      quotes: (json['quotes'] as List? ?? const [])
          .map((item) => SaleQuote.fromJson(_map(item)))
          .toList(),
    );
  }
}

/// Billet d'une vente, tel que le serveur le renvoie.
class SaleTicket {
  const SaleTicket({
    required this.reference,
    required this.status,
    required this.statusDisplay,
    required this.passengerName,
    required this.seatNumber,
    required this.routeLabel,
    required this.departureAt,
    required this.boardingAt,
    required this.amount,
    required this.currency,
    required this.publicUrl,
    this.boardingDisplay = '',
    this.alightingDisplay = '',
    this.printInfo,
    this.qrToken = '',
  });

  /// Jeton lu par le scanner ; vide tant que le billet n'est pas émis.
  final String qrToken;
  final String reference;
  final String status;
  final String statusDisplay;
  final String passengerName;
  final String seatNumber;
  final String routeLabel;
  final DateTime? departureAt;
  final DateTime? boardingAt;
  final num amount;
  final String currency;

  /// Adresse publique du billet ; vide tant que le serveur n'a pas d'adresse de site configurée.
  final String publicUrl;

  final String boardingDisplay;
  final String alightingDisplay;

  /// Données imprimées sur le billet (fiscalité, IFU acheteur, mode de paiement).
  final TicketPrintInfo? printInfo;

  bool get isIssued => status == 'ISSUED';

  factory SaleTicket.fromJson(Map<String, dynamic> json) {
    final trip = _map(json['trip_detail']);
    final segment = json['segment_label'] as String? ?? '';
    final info = json['print_info'] is Map
        ? TicketPrintInfo.fromJson(_map(json['print_info']))
        : null;
    final bDisp = (json['boarding_display'] as String? ?? '').trim();
    final aDisp = (json['alighting_display'] as String? ?? '').trim();
    return SaleTicket(
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      passengerName: json['passenger_name'] as String? ?? '',
      seatNumber: _map(json['seat_detail'])['number'] as String? ?? '',
      routeLabel: segment.isNotEmpty
          ? segment
          : (_map(trip['route_detail'])['label'] as String? ?? ''),
      departureAt: _date(json['effective_departure_at'] ?? trip['departure_at']),
      boardingAt: _date(trip['boarding_at']),
      amount: _num(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
      publicUrl: json['public_url'] as String? ?? '',
      boardingDisplay: bDisp.isNotEmpty ? bDisp : (info?.boardingDisplay.trim() ?? ''),
      alightingDisplay: aDisp.isNotEmpty ? aDisp : (info?.alightingDisplay.trim() ?? ''),
      printInfo: info,
      qrToken: json['qr_token'] as String? ?? '',
    );
  }
}

/// Vente en cours ou terminée.
class Sale {
  const Sale({
    required this.id,
    required this.status,
    required this.expiresAt,
    required this.ticket,
  });

  final int id;

  /// HELD (place tenue, paiement attendu), CONFIRMED (billet émis), EXPIRED, CANCELLED, REFUND_DUE.
  final String status;
  final DateTime? expiresAt;
  final SaleTicket? ticket;

  bool get isHeld => status == 'HELD';
  bool get isIssued => status == 'CONFIRMED' && (ticket?.isIssued ?? false);
  bool get isOver =>
      status == 'EXPIRED' || status == 'CANCELLED' || status == 'REFUND_DUE';

  factory Sale.fromJson(Map<String, dynamic> json) {
    final tickets = json['tickets'] as List? ?? const [];
    return Sale(
      id: json['id'] as int,
      status: json['status'] as String? ?? '',
      expiresAt: _date(json['reservation_expires_at']),
      ticket: tickets.isEmpty ? null : SaleTicket.fromJson(_map(tickets.first)),
    );
  }
}

/// Transaction Mobile Money créée par le serveur chez le prestataire.
class SaleCheckout {
  const SaleCheckout({
    required this.transactionId,
    required this.paymentUrl,
    required this.paymentMethod,
    required this.total,
    required this.currency,
  });

  final String transactionId;
  final String? paymentUrl;
  final int paymentMethod;
  final num total;
  final String currency;

  factory SaleCheckout.fromJson(Map<String, dynamic> json) => SaleCheckout(
    transactionId: '${json['transaction_id']}',
    paymentUrl: json['payment_url'] as String?,
    paymentMethod: json['payment_method'] as int,
    total: _num(json['total']),
    currency: json['currency'] as String? ?? 'XOF',
  );
}

/// Texte de partage du billet : uniquement des valeurs du serveur ; le lien n'apparaît que s'il existe.
String saleShareText(SaleTicket ticket, String Function(DateTime) formatDate) {
  final info = ticket.printInfo;
  final paid = (info != null && info.paid) || ticket.isIssued;
  final bDisp = ticket.boardingDisplay.trim();
  final aDisp = ticket.alightingDisplay.trim();
  return [
    'AXIS Transport',
    'Billet : ${ticket.reference}',
    'Passager : ${ticket.passengerName}',
    'Trajet : ${ticket.routeLabel}',
    if (bDisp.isNotEmpty) 'Embarquement : $bDisp',
    if (aDisp.isNotEmpty) 'Débarquement : $aDisp',
    if (ticket.boardingAt != null)
      '${bDisp.isNotEmpty ? "Heure d'embarquement" : "Embarquement"} : ${formatDate(ticket.boardingAt!)}',
    if (ticket.departureAt != null)
      'Départ : ${formatDate(ticket.departureAt!)}',
    'Siège : ${ticket.seatNumber}',
    'Prix du billet : ${formatMoney(ticket.amount, ticket.currency)}',
    if (paid) 'Statut : Payé',
    if (info != null && info.sale.trim().isNotEmpty)
      info.sale.trim().startsWith('Vendeur')
          ? info.sale.trim()
          : 'Vendeur : ${info.sale.trim()}',
    if (info != null && info.paymentMode.trim().isNotEmpty)
      'Mode de paiement : ${info.paymentMode.trim()}',
    if (info != null && info.buyerIfu.trim().isNotEmpty)
      'IFU de l\'acheteur : ${info.buyerIfu.trim()}',
    if (ticket.publicUrl.isNotEmpty) ...[
      '',
      'Votre billet : ${ticket.publicUrl}',
    ],
    '',
    ...ticketFooterLines(info),
  ].join('\n');
}
