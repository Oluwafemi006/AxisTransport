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

class Place {
  const Place({required this.id, required this.name, required this.address});

  final int id;
  final String name;
  final String address;

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'address': address};
}

class RouteInfo {
  const RouteInfo({
    required this.id,
    required this.label,
    this.origin,
    this.destination,
  });

  final int id;
  final String label;
  final Place? origin;
  final Place? destination;

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
  });

  final int id;
  final String code;
  final String label;
  final bool active;
  final double feePercentage;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as int,
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      active: json['active'] as bool? ?? false,
      feePercentage: (json['fee_percentage'] is num)
          ? (json['fee_percentage'] as num).toDouble()
          : double.tryParse(json['fee_percentage']?.toString() ?? '0') ?? 0.0,
    );
  }
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
    this.reservationExpiresAt,
  });

  final int id;
  final String reference;
  final Trip trip;
  final Seat seat;
  final String passengerName;
  final String passengerPhone;
  final String status;
  final String statusDisplay;
  final String qrToken;
  final num amount;
  final String currency;
  final DateTime? reservationExpiresAt;

  bool get isConfirmed =>
      status == 'ISSUED' || status == 'CHECKED' || status == 'COMPLETED';

  factory Ticket.fromJson(Map<String, dynamic> json) {
    return Ticket(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      trip: Trip.fromJson(json['trip_detail'] as Map<String, dynamic>),
      seat: Seat.fromJson(json['seat_detail'] as Map<String, dynamic>),
      passengerName: json['passenger_name'] as String? ?? '',
      passengerPhone: json['passenger_phone'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
      qrToken: json['qr_token'] as String? ?? '',
      amount: asNum(json['amount']),
      currency: json['currency'] as String? ?? 'XOF',
      reservationExpiresAt: json['reservation_expires_at'] == null
          ? null
          : DateTime.parse(json['reservation_expires_at'] as String).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reference': reference,
    'trip_detail': trip.toJson(),
    'seat_detail': seat.toJson(),
    'passenger_name': passengerName,
    'passenger_phone': passengerPhone,
    'status': status,
    'status_display': statusDisplay,
    'qr_token': qrToken,
    'amount': amount,
    'currency': currency,
    'reservation_expires_at': reservationExpiresAt?.toUtc().toIso8601String(),
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
    this.guestAccessToken,
    this.reservationExpiresAt,
  });

  final int id;
  final String reference;
  final String status;
  final String statusDisplay;
  final num amount;
  final String currency;
  final List<Ticket> tickets;
  final String? guestAccessToken;
  final DateTime? reservationExpiresAt;

  bool get isConfirmed => status == 'CONFIRMED';

  factory BookingReservation.fromJson(Map<String, dynamic> json) {
    final tickets = json['tickets'] as List? ?? const [];
    return BookingReservation(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? '',
      statusDisplay: json['status_display'] as String? ?? '',
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
