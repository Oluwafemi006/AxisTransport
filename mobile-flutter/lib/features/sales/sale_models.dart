// Données de la vente par un agent, lues telles quelles dans les réponses du serveur.
// L'application ne calcule ni prix, ni frais, ni disponibilité.

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
  });

  final int id;
  final String label;
  final DateTime? departureAt;
  final DateTime? boardingAt;
  final int availableSeats;

  /// Vide quand aucun tarif n'est défini en base : le départ n'est alors pas vendable.
  final List<SaleQuote> quotes;

  bool get hasFare => quotes.isNotEmpty;

  factory SaleTrip.fromJson(Map<String, dynamic> json) => SaleTrip(
    id: json['id'] as int,
    label: _map(json['route_detail'])['label'] as String? ?? '',
    departureAt: _date(json['departure_at']),
    boardingAt: _date(json['boarding_at']),
    availableSeats: json['available_seats'] as int? ?? 0,
    quotes: (json['quotes'] as List? ?? const [])
        .map((item) => SaleQuote.fromJson(_map(item)))
        .toList(),
  );
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
  });

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

  bool get isIssued => status == 'ISSUED';

  factory SaleTicket.fromJson(Map<String, dynamic> json) {
    final trip = _map(json['trip_detail']);
    return SaleTicket(
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      passengerName: json['passenger_name'] as String? ?? '',
      seatNumber: _map(json['seat_detail'])['number'] as String? ?? '',
      routeLabel: _map(trip['route_detail'])['label'] as String? ?? '',
      departureAt: _date(trip['departure_at']),
      boardingAt: _date(trip['boarding_at']),
      amount: _num(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
      publicUrl: json['public_url'] as String? ?? '',
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
  return [
    'AXIS Transport',
    'Billet : ${ticket.reference}',
    'Passager : ${ticket.passengerName}',
    'Trajet : ${ticket.routeLabel}',
    if (ticket.boardingAt != null)
      'Embarquement : ${formatDate(ticket.boardingAt!)}',
    if (ticket.departureAt != null)
      'Départ : ${formatDate(ticket.departureAt!)}',
    'Siège : ${ticket.seatNumber}',
    if (ticket.publicUrl.isNotEmpty) ...[
      '',
      'Votre billet : ${ticket.publicUrl}',
    ],
  ].join('\n');
}
