import 'package:axis_transport_flutter/features/sales/sale_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _trip({bool? departed}) => {
  'id': 5,
  'route_detail': {'label': 'Parakou → Cotonou', 'stops': []},
  'departure_at': '2026-11-06T07:00:00Z',
  'available_seats': 10,
  'quotes': [],
  'segments': [
    {
      'origin_id': 1,
      'origin': 'Savè',
      'destination_id': 2,
      'destination': 'Cotonou',
      'quotes': [],
    },
  ],
  'departed': ?departed,
};

void main() {
  test('« déjà parti » : lu sur le départ et sur chacun de ses tronçons', () {
    final choices = SaleTrip.choicesFromJson(_trip(departed: true));
    expect(choices.single.departed, isTrue);
    expect(SaleTrip.fromJson(_trip(departed: true)).departed, isTrue);
  });

  test('champ absent (ancien serveur) : départ à venir', () {
    expect(SaleTrip.fromJson(_trip()).departed, isFalse);
  });
}
