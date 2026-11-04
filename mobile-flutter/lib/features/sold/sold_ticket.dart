/// Billet vendu aujourd'hui, tel que le serveur le renvoie (rien n'est recalculé ici).
class SoldTicket {
  const SoldTicket({
    required this.reference,
    required this.route,
    required this.seat,
    required this.passengerName,
    required this.passengerPhone,
    required this.amountFcfa,
    required this.statusDisplay,
    required this.soldAt,
    required this.soldByName,
    required this.publicUrl,
  });

  factory SoldTicket.fromJson(Map<String, dynamic> json) => SoldTicket(
    reference: json['reference'] as String? ?? '',
    route: json['route'] as String? ?? '',
    seat: '${json['seat'] ?? ''}',
    passengerName: json['passenger_name'] as String? ?? '',
    passengerPhone: json['passenger_phone'] as String? ?? '',
    amountFcfa: (json['amount_fcfa'] as num?)?.toInt() ?? 0,
    statusDisplay: json['status_display'] as String? ?? '',
    soldAt: DateTime.tryParse(json['sold_at'] as String? ?? '')?.toLocal(),
    soldByName: json['sold_by_name'] as String? ?? '',
    publicUrl: json['public_url'] as String? ?? '',
  );

  final String reference;
  final String route;
  final String seat;
  final String passengerName;
  final String passengerPhone;
  final int amountFcfa;
  final String statusDisplay;
  final DateTime? soldAt;
  final String soldByName;
  final String publicUrl;

  String get message {
    final link = publicUrl.isEmpty ? '' : ' : $publicUrl';
    return 'Bonjour $passengerName, voici votre billet AXIS Transport $reference$link';
  }
}

/// Lien WhatsApp du billet : texte prérempli. Numéro du passager seulement s'il est au format
/// international (« + » ou « 00 ») ; sinon WhatsApp laisse l'agent choisir le contact (aucun indicatif deviné).
Uri whatsappTicketUri(SoldTicket ticket) {
  final compact = ticket.passengerPhone.replaceAll(RegExp(r'[\s.\-()]'), '');
  final match = RegExp(r'^(?:\+|00)(\d{1,15})$').firstMatch(compact);
  final path = match == null ? '' : match.group(1)!;
  return Uri.parse('https://wa.me/$path?text=${Uri.encodeComponent(ticket.message)}');
}

/// Montant en francs CFA, espaces fines entre milliers.
String formatFcfa(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$buffer FCFA';
}
