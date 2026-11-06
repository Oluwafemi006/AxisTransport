import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/features/rentals/rentals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({bool rentable = true, String photo = '', bool driverRequired = false}) => {
      'id': 4,
      'name': 'TEST voiture',
      'category': 'RENTAL',
      'capacity': 4,
      'state': rentable ? 'ACTIVE' : 'MAINTENANCE',
      'description': '',
      'rental_daily_rate': '20000.00',
      'driver_available': driverRequired,
      'rental_daily_rate_with_driver': '30000.00',
      'driver_required': driverRequired,
      'brand': 'TEST marque',
      'model_name': 'TEST modèle',
      'transmission_display': 'Automatique',
      'fuel_display': 'Diesel',
      'photo_url': photo,
      'rentable': rentable,
    };

Future<void> _card(WidgetTester tester, Vehicle vehicle) async {
  await tester.pumpWidget(MaterialApp(
    theme: AxisTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: RentalVehicleCard(vehicle: vehicle, withDriver: false, onSwitchMode: (_) {}, onReserve: () {}),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  test('lecture : « avec chauffeur uniquement », caractéristiques, photo, disponibilité', () {
    final vehicle = Vehicle.fromJson(_json(driverRequired: true, rentable: false, photo: 'https://test.invalid/v.jpg'));
    expect(vehicle.onlyWithDriver, isTrue);
    expect(vehicle.dailyRateWithDriver, 30000);
    expect((vehicle.brand, vehicle.modelName, vehicle.fuelDisplay), ('TEST marque', 'TEST modèle', 'Diesel'));
    expect(vehicle.photoUrl, 'https://test.invalid/v.jpg');
    expect(vehicle.rentable, isFalse);
  });

  test('ancien serveur sans « rentable » : véhicule demandable', () {
    final json = _json()..remove('rentable');
    expect(Vehicle.fromJson(json).rentable, isTrue);
  });

  testWidgets('sans photo : image de secours ; disponible : bouton Réserver', (tester) async {
    await _card(tester, Vehicle.fromJson(_json()));
    expect(find.byKey(const Key('vehicle-photo-fallback')), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);
    expect(find.text('TEST marque TEST modèle'), findsOneWidget);
  });

  testWidgets('indisponible : affiché, bouton « Indisponible » inactif', (tester) async {
    await _card(tester, Vehicle.fromJson(_json(rentable: false)));
    expect(find.byKey(const Key('vehicle-unavailable')), findsOneWidget);
    expect(find.text('Réserver'), findsNothing);
  });
}
