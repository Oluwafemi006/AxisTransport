import 'package:axis_transport_flutter/features/rentals/rentals_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Demande de location : champs obligatoires (mêmes messages que le site)', () {
    String? check({String name = 'Locataire TEST', String cip = 'CIP-TEST', String licence = 'PERMIS-TEST', int? zone = 1}) =>
        rentalIdentityError(fullName: name, cipNumber: cip, licenceNumber: licence, zone: zone);

    test('tout est rempli', () => expect(check(), isNull));
    test('nom manquant', () => expect(check(name: '  '), 'Indiquez le nom et les prénoms.'));
    test('CIP manquant', () => expect(check(cip: ''), 'Indiquez le numéro du CIP.'));
    test('permis manquant', () => expect(check(licence: ''), 'Indiquez le numéro du permis de conduire.'));
    test('zone manquante', () => expect(check(zone: null), 'Choisissez la zone de circulation du véhicule.'));
  });
}
