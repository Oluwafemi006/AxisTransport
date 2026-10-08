enum PassengerType { adult, child }

extension PassengerTypeLabel on PassengerType {
  String get label => this == PassengerType.adult ? 'Adulte' : 'Enfant';
  String get apiValue => this == PassengerType.adult ? 'ADULT' : 'CHILD';
}

class Passenger {
  const Passenger({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.type,
  });

  final String id;
  final String fullName;
  final String phone;
  final PassengerType type;

  Passenger copyWith({String? fullName, String? phone, PassengerType? type}) {
    return Passenger(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      type: type ?? this.type,
    );
  }
}
