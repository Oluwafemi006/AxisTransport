num asNum(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value;
  return num.parse(value.toString());
}

class User {
  const User({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.role,
  });

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String phone;
  final String role;

  bool get isClient => role == 'CLIENT';

  /// Personnel Axis : guichet, contrôleur, administrateur (rôle renvoyé par le serveur).
  bool get isStaff => const {'COUNTER', 'CONTROLLER', 'ADMIN'}.contains(role);

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'first_name': firstName,
    'last_name': lastName,
    'phone': phone,
    'role': role,
  };

  String get displayName {
    final full = [
      firstName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');
    return full.isEmpty ? username : full;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'CLIENT',
    );
  }
}

class BoardingPointInfo {
  const BoardingPointInfo({
    required this.id,
    required this.name,
    this.order = 1,
    this.active = true,
  });

  final int id;
  final String name;
  final int order;
  final bool active;

  factory BoardingPointInfo.fromJson(Map<String, dynamic> json) {
    return BoardingPointInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      order: json['order'] as int? ?? 1,
      active: json['active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    'active': active,
  };
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.address,
    this.boardingPoints = const [],
  });

  final int id;
  final String name;
  final String address;
  final List<BoardingPointInfo> boardingPoints;

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      boardingPoints: (json['boarding_points'] as List<dynamic>?)
              ?.map((item) => BoardingPointInfo.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    if (boardingPoints.isNotEmpty)
      'boarding_points': [for (final p in boardingPoints) p.toJson()],
  };
}

class RouteStopInfo {
  const RouteStopInfo({
    required this.id,
    required this.name,
    required this.position,
    this.boardingPoints = const [],
  });

  final int id;
  final String name;
  final int position;
  final List<BoardingPointInfo> boardingPoints;

  factory RouteStopInfo.fromJson(Map<String, dynamic> json) {
    return RouteStopInfo(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      position: json['position'] as int? ?? 0,
      boardingPoints: (json['boarding_points'] as List<dynamic>?)
              ?.map((item) => BoardingPointInfo.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'position': position,
    if (boardingPoints.isNotEmpty)
      'boarding_points': [for (final p in boardingPoints) p.toJson()],
  };
}

class RouteInfo {
  const RouteInfo({
    required this.id,
    required this.label,
    this.origin,
    this.destination,
    this.stops = const [],
  });

  final int id;
  final String label;
  final Place? origin;
  final Place? destination;
  final List<RouteStopInfo> stops;

  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    return RouteInfo(
      id: json['id'] as int,
      label: json['label'] as String? ?? '',
      origin: json['origin_detail'] is Map<String, dynamic>
          ? Place.fromJson(json['origin_detail'] as Map<String, dynamic>)
          : null,
      destination: json['destination_detail'] is Map<String, dynamic>
          ? Place.fromJson(json['destination_detail'] as Map<String, dynamic>)
          : null,
      stops: (json['stops'] as List<dynamic>?)
              ?.map((item) => RouteStopInfo.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'origin_detail': origin?.toJson(),
    'destination_detail': destination?.toJson(),
  };
}

class Fare {
  const Fare({
    required this.id,
    required this.name,
    required this.amount,
    required this.currency,
  });

  final int id;
  final String name;
  final num amount;
  final String currency;

  factory Fare.fromJson(Map<String, dynamic> json) {
    return Fare(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      amount: asNum(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
    );
  }
}

class Trip {
  const Trip({
    required this.id,
    required this.route,
    required this.departureAt,
    required this.status,
    required this.statusDisplay,
    required this.note,
    required this.availableSeats,
    this.currentFare,
    this.arrivalAt,
    this.boardingAt,
    this.vehicleName,
  });

  final int id;
  final RouteInfo route;
  final DateTime departureAt;
  final String status;
  final String statusDisplay;
  final String note;
  final int availableSeats;
  final Fare? currentFare;
  final DateTime? arrivalAt;

  /// Heure d'embarquement à l'origine, calculée par le serveur (départ moins l'avance réglée).
  final DateTime? boardingAt;
  final String? vehicleName;

  bool get isDemo => note.startsWith('[DÉMO]');

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'] as int,
      route: RouteInfo.fromJson(json['route_detail'] as Map<String, dynamic>),
      departureAt: DateTime.parse(json['departure_at'] as String).toLocal(),
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      note: json['note'] as String? ?? '',
      availableSeats: json['available_seats'] as int? ?? 0,
      arrivalAt: json['arrival_at'] == null
          ? null
          : DateTime.parse(json['arrival_at'] as String).toLocal(),
      boardingAt: json['boarding_at'] == null
          ? null
          : DateTime.parse(json['boarding_at'] as String).toLocal(),
      vehicleName: json['vehicle_detail'] is Map<String, dynamic>
          ? (json['vehicle_detail'] as Map<String, dynamic>)['name'] as String?
          : null,
      currentFare: json['current_fare'] == null
          ? null
          : Fare.fromJson(json['current_fare'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'route_detail': route.toJson(),
    'departure_at': departureAt.toUtc().toIso8601String(),
    'status': status,
    'status_display': statusDisplay,
    'note': note,
    'available_seats': availableSeats,
    'arrival_at': arrivalAt?.toUtc().toIso8601String(),
    'boarding_at': boardingAt?.toUtc().toIso8601String(),
    'vehicle_detail': vehicleName == null ? null : {'name': vehicleName},
    'current_fare': currentFare == null
        ? null
        : {
            'id': currentFare!.id,
            'name': currentFare!.name,
            'amount': currentFare!.amount,
            'currency': currentFare!.currency,
          },
  };
}

class TripBanner {
  const TripBanner({
    required this.bannerText,
    required this.todayTripsCount,
    required this.hasDepartureToday,
  });

  final String bannerText;
  final int todayTripsCount;
  final bool hasDepartureToday;

  factory TripBanner.fromJson(Map<String, dynamic> json) {
    return TripBanner(
      bannerText: json['banner_text'] as String? ?? '',
      todayTripsCount: json['today_trips_count'] as int? ?? 0,
      hasDepartureToday: json['has_departure_today'] as bool? ?? false,
    );
  }
}

class NextAvailable {
  const NextAvailable({
    required this.tripId,
    required this.date,
    required this.departureAt,
    required this.formattedDate,
    required this.formattedTime,
    this.routeLabel,
  });

  final int tripId;
  final DateTime date;
  final DateTime departureAt;
  final String formattedDate;
  final String formattedTime;
  final String? routeLabel;

  factory NextAvailable.fromJson(Map<String, dynamic> json) {
    return NextAvailable(
      tripId: json['trip_id'] as int,
      date: DateTime.parse(json['date'] as String),
      departureAt: DateTime.parse(json['departure_at'] as String).toLocal(),
      formattedDate: json['formatted_date'] as String? ?? '',
      formattedTime: json['formatted_time'] as String? ?? '',
      routeLabel: json['route_label'] as String?,
    );
  }
}

class Seat {
  const Seat({
    required this.id,
    required this.number,
    required this.status,
    this.allowedPassengerTypes = const [],
    this.row,
    this.column,
  });

  final int id;
  final String number;
  final String status;
  final List<String> allowedPassengerTypes;
  final int? row;
  final int? column;

  bool get isAvailable => status == 'AVAILABLE';
  bool allowsPassengerType(String type) =>
      allowedPassengerTypes.isEmpty || allowedPassengerTypes.contains(type);

  factory Seat.fromJson(Map<String, dynamic> json) {
    final allowed = json['allowed_passenger_types'] as List? ?? const [];
    return Seat(
      id: json['id'] as int,
      number: json['number'] as String? ?? '',
      status: json['status'] as String? ?? 'AVAILABLE',
      allowedPassengerTypes: allowed.map((item) => item.toString()).toList(),
      row: json['row'] as int?,
      column: json['column'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'status': status,
    'allowed_passenger_types': allowedPassengerTypes,
    'row': row,
    'column': column,
  };
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.code,
    required this.label,
    required this.active,
    this.feePercentage = 0.0,
    this.online = false,
  });

  final int id;
  final String code;
  final String label;
  final bool active;
  final double feePercentage;

  /// Vrai si le moyen se paie en ligne ; faux s'il n'est encaissable qu'au guichet.
  final bool online;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as int,
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      active: json['active'] as bool? ?? false,
      feePercentage: (json['fee_percentage'] is num)
          ? (json['fee_percentage'] as num).toDouble()
          : double.tryParse(json['fee_percentage']?.toString() ?? '0') ?? 0.0,
      online: json['online'] as bool? ?? false,
    );
  }
}

/// Montant à payer pour un moyen de paiement, calculé par le serveur (frais inclus).
class PaymentQuote {
  const PaymentQuote({
    required this.paymentMethod,
    required this.amount,
    required this.feeAmount,
    required this.total,
    required this.currency,
  });

  final int paymentMethod;
  final num amount;
  final num feeAmount;
  final num total;
  final String currency;

  factory PaymentQuote.fromJson(Map<String, dynamic> json) {
    return PaymentQuote(
      paymentMethod: json['payment_method'] as int,
      amount: asNum(json['amount']),
      feeAmount: asNum(json['fee_amount']),
      total: asNum(json['total']),
      currency: json['currency'] as String? ?? 'XOF',
    );
  }
}

/// Transaction créée par le serveur chez le prestataire de paiement.
class PaymentCheckout {
  const PaymentCheckout({
    required this.transactionId,
    required this.quote,
    this.paymentUrl,
  });

  final String transactionId;
  final String? paymentUrl;
  final PaymentQuote quote;

  factory PaymentCheckout.fromJson(Map<String, dynamic> json) {
    return PaymentCheckout(
      transactionId: json['transaction_id'].toString(),
      paymentUrl: json['payment_url'] as String?,
      quote: PaymentQuote.fromJson(json),
    );
  }
}

/// Informations de l'agence imprimées sur le billet. Vide = « À renseigner ». Jamais de comptes bancaires.
class AgencyInfo {
  const AgencyInfo({
    this.legalName = '',
    this.ifu = '',
    this.rccm = '',
    this.address = '',
    this.phones = '',
    this.email = '',
  });

  final String legalName;
  final String ifu;
  final String rccm;
  final String address;
  final String phones;
  final String email;

  factory AgencyInfo.fromJson(Map<String, dynamic> json) => AgencyInfo(
    legalName: json['legal_name'] as String? ?? '',
    ifu: json['ifu'] as String? ?? '',
    rccm: json['rccm'] as String? ?? '',
    address: json['address'] as String? ?? '',
    phones: json['phones'] as String? ?? '',
    email: json['email'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'legal_name': legalName,
    'ifu': ifu,
    'rccm': rccm,
    'address': address,
    'phones': phones,
    'email': email,
  };
}

class TaxLine {
  const TaxLine({required this.name, required this.rate, required this.amount});

  final String name;
  final String rate;
  final num amount;

  factory TaxLine.fromJson(Map<String, dynamic> json) => TaxLine(
    name: json['name'] as String? ?? '',
    rate: json['rate']?.toString() ?? '',
    amount: asNum(json['amount']),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'rate': rate,
    'amount': amount,
  };
}

/// Données imprimées sur le billet, préparées par le serveur ; l'application ne calcule rien.
class TicketPrintInfo {
  const TicketPrintInfo({
    this.paid = false,
    this.sale = '',
    this.paymentMode = '',
    this.buyerIfu = '',
    this.boardingPlace = '',
    this.origin = '',
    this.destination = '',
    this.boardingPointName = '',
    this.alightingPointName = '',
    this.boardingDisplay = '',
    this.alightingDisplay = '',
    this.segmentLabel = '',
    this.departureLabel = '',
    this.departureAt,
    this.isOffset = false,
    this.priceInclTax = 0,
    this.priceExclTax,
    this.taxLines = const [],
    this.agency = const AgencyInfo(),
    this.conditions = '',
  });

  final bool paid;
  final String sale;
  final String paymentMode;
  final String buyerIfu;
  final String boardingPlace;
  final String origin;
  final String destination;
  final String boardingPointName;
  final String alightingPointName;
  final String boardingDisplay;
  final String alightingDisplay;
  final String segmentLabel;
  final String departureLabel;
  final DateTime? departureAt;
  final bool isOffset;
  final num priceInclTax;

  /// Prix HT : fourni seulement si l'IFU de l'agence est renseigné.
  final num? priceExclTax;
  final List<TaxLine> taxLines;
  final AgencyInfo agency;
  final String conditions;

  factory TicketPrintInfo.fromJson(Map<String, dynamic> json) =>
      TicketPrintInfo(
        paid: json['paid'] as bool? ?? false,
        sale: json['sale'] as String? ?? '',
        paymentMode: json['payment_mode'] as String? ?? '',
        buyerIfu: json['buyer_ifu'] as String? ?? '',
        boardingPlace: json['boarding_place'] as String? ?? '',
        origin: json['origin'] as String? ?? '',
        destination: json['destination'] as String? ?? '',
        boardingPointName: json['boarding_point_name'] as String? ?? '',
        alightingPointName: json['alighting_point_name'] as String? ?? '',
        boardingDisplay: json['boarding_display'] as String? ?? '',
        alightingDisplay: json['alighting_display'] as String? ?? '',
        segmentLabel: json['segment_label'] as String? ?? '',
        departureLabel: json['departure_label'] as String? ?? '',
        departureAt: json['departure_at'] == null
            ? null
            : DateTime.parse(json['departure_at'] as String).toLocal(),
        isOffset: json['is_offset'] as bool? ?? false,
        priceInclTax: asNum(json['price_incl_tax']),
        priceExclTax: json['price_excl_tax'] == null
            ? null
            : asNum(json['price_excl_tax']),
        taxLines: [
          for (final item in (json['tax_lines'] as List<dynamic>? ?? const []))
            TaxLine.fromJson(item as Map<String, dynamic>),
        ],
        agency: json['agency'] is Map<String, dynamic>
            ? AgencyInfo.fromJson(json['agency'] as Map<String, dynamic>)
            : const AgencyInfo(),
        conditions: json['conditions'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'paid': paid,
    'sale': sale,
    'payment_mode': paymentMode,
    'buyer_ifu': buyerIfu,
    'boarding_place': boardingPlace,
    'origin': origin,
    'destination': destination,
    'boarding_point_name': boardingPointName,
    'alighting_point_name': alightingPointName,
    'boarding_display': boardingDisplay,
    'alighting_display': alightingDisplay,
    'segment_label': segmentLabel,
    'departure_label': departureLabel,
    'departure_at': departureAt?.toUtc().toIso8601String(),
    'is_offset': isOffset,
    'price_incl_tax': priceInclTax,
    'price_excl_tax': priceExclTax,
    'tax_lines': [for (final line in taxLines) line.toJson()],
    'agency': agency.toJson(),
    'conditions': conditions,
  };
}

const ticketMissingValue = 'À renseigner';

String _orMissingTicketValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? ticketMissingValue : text;
}

/// Bas du billet (mentions légales et conditions de l'agence) : vide = « À renseigner ».
/// Jamais de comptes bancaires.
List<String> ticketFooterLines(TicketPrintInfo? info) {
  final agency = info?.agency ?? const AgencyInfo();
  final contacts = [
    agency.phones,
    agency.email,
  ].map((item) => item.trim()).where((item) => item.isNotEmpty).join(' · ');
  return [
    'Raison sociale : ${_orMissingTicketValue(agency.legalName)}',
    'IFU : ${_orMissingTicketValue(agency.ifu)} · RCCM : ${_orMissingTicketValue(agency.rccm)}',
    'Adresse : ${_orMissingTicketValue(agency.address)}',
    'Contacts : ${_orMissingTicketValue(contacts)}',
    'Conditions : ${_orMissingTicketValue(info?.conditions)}',
  ];
}

class Ticket {
  const Ticket({
    required this.id,
    required this.reference,
    required this.trip,
    required this.seat,
    required this.passengerName,
    required this.passengerPhone,
    required this.status,
    required this.statusDisplay,
    required this.qrToken,
    required this.amount,
    required this.currency,
    this.originName,
    this.destinationName,
    this.boardingPointName,
    this.alightingPointName,
    this.boardingDisplay,
    this.alightingDisplay,
    this.segmentLabel,
    this.departureLabel,
    this.effectiveDepartureAt,
    this.reservationExpiresAt,
    this.publicUrl = '',
    this.printInfo,
    this.bookingId,
    this.seatPreference = true,
    this.seatSummaryLabel,
  });

  final int id;
  final String reference;

  /// Réservation à laquelle appartient le billet (null pour un ancien billet vendu seul).
  final int? bookingId;
  final Trip trip;
  final Seat seat;
  final String passengerName;
  final String passengerPhone;
  final String status;
  final String statusDisplay;
  final String qrToken;
  final num amount;
  final String currency;
  final String? originName;
  final String? destinationName;
  final String? boardingPointName;
  final String? alightingPointName;
  final String? boardingDisplay;
  final String? alightingDisplay;
  final String? segmentLabel;
  final String? departureLabel;
  final DateTime? effectiveDepartureAt;
  final DateTime? reservationExpiresAt;

  /// Adresse publique du billet, fournie par le serveur (vide si absente).
  final String publicUrl;

  /// Données d'impression (vendeur, mode de paiement, agence, taxes) ; absentes sur un ancien billet en cache.
  final TicketPrintInfo? printInfo;

  /// Vrai si le client a choisi son siège ; faux si le siège a été attribué automatiquement.
  final bool seatPreference;

  /// Libellé du siège selon l'étape (avant paiement : préférence ou attribution après paiement ; après paiement : numéro définitif).
  final String? seatSummaryLabel;

  bool get isConfirmed =>
      status == 'ISSUED' || status == 'CHECKED' || status == 'COMPLETED';

  /// Réservé, en attente de paiement : le client peut demander de vérifier son paiement.
  bool get awaitsPayment => status == 'HELD' && bookingId != null;

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      bookingId: json['booking'] as int?,
      publicUrl: json['public_url'] as String? ?? '',
      printInfo: json['print_info'] is Map<String, dynamic>
          ? TicketPrintInfo.fromJson(json['print_info'] as Map<String, dynamic>)
          : null,
      trip: Trip.fromJson(json['trip_detail'] as Map<String, dynamic>),
      seat: Seat.fromJson(json['seat_detail'] as Map<String, dynamic>),
      passengerName: json['passenger_name'] as String? ?? '',
      passengerPhone: json['passenger_phone'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      qrToken: json['qr_token'] as String? ?? '',
      amount: asNum(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
      originName: json['origin_name'] as String?,
      destinationName: json['destination_name'] as String?,
      boardingPointName: json['boarding_point_name'] as String?,
      alightingPointName: json['alighting_point_name'] as String?,
      boardingDisplay: json['boarding_display'] as String?,
      alightingDisplay: json['alighting_display'] as String?,
      segmentLabel: json['segment_label'] as String?,
      departureLabel: json['departure_label'] as String?,
      effectiveDepartureAt: json['effective_departure_at'] == null
          ? null
          : DateTime.parse(json['effective_departure_at'] as String).toLocal(),
      reservationExpiresAt: json['reservation_expires_at'] == null
          ? null
          : DateTime.parse(json['reservation_expires_at'] as String).toLocal(),
      seatPreference: json['seat_preference'] as bool? ?? true,
      seatSummaryLabel: json['seat_summary_label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'booking': bookingId,
    'public_url': publicUrl,
    if (printInfo != null) 'print_info': printInfo!.toJson(),
    'trip_detail': trip.toJson(),
    'seat_detail': seat.toJson(),
    'passenger_name': passengerName,
    'passenger_phone': passengerPhone,
    'status': status,
    'status_display': statusDisplay,
    'qr_token': qrToken,
    'amount': amount,
    'currency': currency,
    'origin_name': originName,
    'destination_name': destinationName,
    'boarding_point_name': boardingPointName,
    'alighting_point_name': alightingPointName,
    'boarding_display': boardingDisplay,
    'alighting_display': alightingDisplay,
    'segment_label': segmentLabel,
    'departure_label': departureLabel,
    'effective_departure_at': effectiveDepartureAt?.toUtc().toIso8601String(),
    'reservation_expires_at': reservationExpiresAt?.toUtc().toIso8601String(),
    'seat_preference': seatPreference,
    if (seatSummaryLabel != null) 'seat_summary_label': seatSummaryLabel,
  };
}

class BookingReservation {
  const BookingReservation({
    required this.id,
    required this.reference,
    required this.status,
    required this.statusDisplay,
    required this.amount,
    required this.currency,
    required this.tickets,
    this.clientStatusDisplay,
    this.segmentLabel,
    this.originName,
    this.destinationName,
    this.departureLabel,
    this.effectiveDepartureAt,
    this.tripDetail,
    this.paymentQuotes = const [],
    this.guestAccessToken,
    this.reservationExpiresAt,
  });

  final int id;
  final String reference;
  final String status;
  final String statusDisplay;
  final String? clientStatusDisplay;
  final String? segmentLabel;
  final String? originName;
  final String? destinationName;
  final String? departureLabel;
  final DateTime? effectiveDepartureAt;
  final Trip? tripDetail;
  final num amount;
  final String currency;
  final List<Ticket> tickets;
  final List<PaymentQuote> paymentQuotes;
  final String? guestAccessToken;
  final DateTime? reservationExpiresAt;

  bool get isConfirmed => status == 'CONFIRMED';

  bool get isExpired {
    final expiresAt = reservationExpiresAt;
    return status == 'EXPIRED' ||
        (expiresAt != null && !expiresAt.isAfter(DateTime.now()));
  }

  PaymentQuote? quoteFor(int paymentMethod) {
    for (final quote in paymentQuotes) {
      if (quote.paymentMethod == paymentMethod) return quote;
    }
    return null;
  }

  factory BookingReservation.fromJson(Map<String, dynamic> json) {
    final tickets = json['tickets'] as List? ?? const [];
    return BookingReservation(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      clientStatusDisplay: json['client_status_display'] as String?,
      segmentLabel: json['segment_label'] as String?,
      originName: json['origin_name'] as String?,
      destinationName: json['destination_name'] as String?,
      departureLabel: json['departure_label'] as String?,
      effectiveDepartureAt: json['effective_departure_at'] == null
          ? null
          : DateTime.parse(json['effective_departure_at'] as String).toLocal(),
      tripDetail: json['trip_detail'] is Map<String, dynamic>
          ? Trip.fromJson(json['trip_detail'] as Map<String, dynamic>)
          : null,
      amount: asNum(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
      guestAccessToken: json['guest_access_token'] as String?,
      reservationExpiresAt: json['reservation_expires_at'] == null
          ? null
          : DateTime.parse(json['reservation_expires_at'] as String).toLocal(),
      tickets: tickets
          .whereType<Map>()
          .map((item) => Ticket.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      paymentQuotes: (json['payment_quotes'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => PaymentQuote.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.category,
    required this.capacity,
    required this.state,
    required this.description,
    required this.dailyRate,
    required this.driverAvailable,
    this.dailyRateWithDriver,
    this.onlyWithDriver = false,
    this.baseLocation,
  });

  final int id;
  final String name;
  final String category;
  final int? capacity;
  final String state;
  final String description;
  final num? dailyRate;
  final bool driverAvailable;
  final num? dailyRateWithDriver;
  final bool onlyWithDriver;
  final Place? baseLocation;

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      capacity: json['capacity'] as int?,
      state: json['state'] as String? ?? '',
      description: json['description'] as String? ?? '',
      dailyRate: json['rental_daily_rate'] == null
          ? null
          : asNum(json['rental_daily_rate']),
      driverAvailable: json['driver_available'] as bool? ?? false,
      dailyRateWithDriver: json['rental_daily_rate_with_driver'] == null
          ? null
          : asNum(json['rental_daily_rate_with_driver']),
      onlyWithDriver: json['only_with_driver'] as bool? ?? false,
      baseLocation: json['base_location_detail'] is Map
          ? Place.fromJson(
              Map<String, dynamic>.from(json['base_location_detail'] as Map),
            )
          : null,
    );
  }
}

class ParcelHistory {
  const ParcelHistory({
    required this.status,
    required this.statusDisplay,
    required this.changedAt,
  });

  final String status;
  final String statusDisplay;
  final DateTime changedAt;

  factory ParcelHistory.fromJson(Map<String, dynamic> json) {
    return ParcelHistory(
      status: json['to_status'] as String? ?? '',
      statusDisplay: json['to_status_display'] as String? ?? '',
      changedAt: DateTime.parse(json['changed_at'] as String).toLocal(),
    );
  }
}

class Parcel {
  const Parcel({
    required this.id,
    required this.trackingNumber,
    required this.senderName,
    required this.recipientName,
    required this.origin,
    required this.destination,
    required this.description,
    required this.status,
    required this.statusDisplay,
    required this.history,
  });

  final int id;
  final String trackingNumber;
  final String senderName;
  final String recipientName;
  final Place origin;
  final Place destination;
  final String description;
  final String status;
  final String statusDisplay;
  final List<ParcelHistory> history;

  factory Parcel.fromJson(Map<String, dynamic> json) {
    final history = json['status_history'] as List? ?? const [];
    return Parcel(
      id: json['id'] as int,
      trackingNumber: json['tracking_number'] as String? ?? '',
      senderName: json['sender_name'] as String? ?? '',
      recipientName: json['recipient_name'] as String? ?? '',
      origin: Place.fromJson(
        Map<String, dynamic>.from(json['origin_detail'] as Map),
      ),
      destination: Place.fromJson(
        Map<String, dynamic>.from(json['destination_detail'] as Map),
      ),
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      history: history
          .whereType<Map>()
          .map(
            (item) => ParcelHistory.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class RentalBooking {
  const RentalBooking({
    required this.id,
    required this.reference,
    required this.vehicle,
    required this.startsAt,
    required this.endsAt,
    required this.withDriver,
    required this.status,
    required this.statusDisplay,
  });

  final int id;
  final String reference;
  final Vehicle vehicle;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool withDriver;
  final String status;
  final String statusDisplay;

  factory RentalBooking.fromJson(Map<String, dynamic> json) {
    return RentalBooking(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      vehicle: Vehicle.fromJson(
        Map<String, dynamic>.from(json['vehicle_detail'] as Map),
      ),
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      withDriver: json['with_driver'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
    );
  }
}

/// Étape du suivi d'un colis telle que le serveur la présente au client.
class ParcelStep {
  const ParcelStep({
    required this.label,
    required this.done,
    required this.current,
    this.reachedAt,
  });

  final String label;
  final bool done;
  final bool current;
  final DateTime? reachedAt;

  factory ParcelStep.fromJson(Map<String, dynamic> json) {
    return ParcelStep(
      label: json['label'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      current: json['current'] as bool? ?? false,
      reachedAt: json['reached_at'] == null
          ? null
          : DateTime.parse(json['reached_at'] as String).toLocal(),
    );
  }
}

class ParcelTracking {
  const ParcelTracking({
    required this.trackingNumber,
    required this.origin,
    required this.destination,
    required this.steps,
    this.photos = const [],
    this.senderLabel,
    this.recipientLabel,
    this.description,
  });

  final String trackingNumber;
  final String origin;
  final String destination;
  final List<ParcelStep> steps;
  final List<String> photos;
  final String? senderLabel;
  final String? recipientLabel;
  final String? description;

  factory ParcelTracking.fromJson(Map<String, dynamic> json) {
    return ParcelTracking(
      trackingNumber: json['tracking_number'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      steps: (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ParcelStep.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      photos: (json['photos'] as List? ?? const [])
          .whereType<String>()
          .where((url) => url.trim().isNotEmpty)
          .take(3)
          .toList(),
      senderLabel: json['sender_label'] as String?,
      recipientLabel: json['recipient_label'] as String?,
      description: json['description'] as String?,
    );
  }
}
