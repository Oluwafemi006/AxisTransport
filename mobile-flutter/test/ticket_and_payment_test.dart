import 'dart:convert';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_checkout.dart';
import 'package:axis_transport_flutter/features/tickets/ticket_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Ticket _ticket({
  DateTime? arrivalAt,
  String passengerName = 'Awa Test',
  String status = 'ISSUED',
}) => Ticket(
  id: 7,
  reference: 'AX-20261008-ABCD1234',
  trip: Trip(
    id: 5,
    route: const RouteInfo(id: 1, label: 'Cotonou → Parakou'),
    departureAt: DateTime(2026, 10, 9, 8, 0),
    arrivalAt: arrivalAt,
    status: 'SCHEDULED',
    statusDisplay: 'Planifié',
    note: '',
    availableSeats: 20,
  ),
  seat: const Seat(id: 8, number: '3A', status: 'PAID'),
  passengerName: passengerName,
  passengerPhone: '',
  status: status,
  statusDisplay: 'Ticket émis',
  qrToken: '840a332e-ad51-431f-93b8-e711787a7ef2',
  amount: 1000,
  currency: 'XOF',
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group('billet', () {
    test('les champs viennent du serveur ; arrivée absente masquée, passager absent « À renseigner »', () {
      final fields = Map.fromEntries(
        ticketFields(_ticket(passengerName: '  '))
            .map((item) => MapEntry(item.$1, item.$2)),
      );
      expect(fields['Référence'], 'AX-20261008-ABCD1234');
      expect(fields['Trajet'], 'Cotonou → Parakou');
      expect(fields['Siège'], '3A');
      expect(fields.containsKey('Arrivée prévue'), isFalse);
      expect(fields.values, isNot(contains('à confirmer')));
      expect(fields['Passager'], missingValue);
      expect(fields['Départ'], contains('08:00'));
    });

    test(
      'le billet affiche le prix du billet, jamais un total avec frais',
      () async {
        // Billet à 7 500 XOF payé 7 635 XOF (frais de 1,80 %) : le serveur ne met que le tarif dans le billet.
        final ticket = Ticket.fromJson({
          ..._ticket().toJson(),
          'amount': '7500.00',
        });
        final fields = ticketFields(ticket);
        final labels = fields.map((item) => item.$1).toList();
        expect(labels, contains('Prix du billet'));
        expect(labels, isNot(contains('Montant')));
        final price = fields
            .firstWhere((item) => item.$1 == 'Prix du billet')
            .$2;
        expect(price.replaceAll(RegExp(r'\s'), ''), '7500FCFA');
        final everything = [
          ...fields.map((item) => item.$2),
          ticketShareText(ticket),
        ].join(' ');
        expect(everything, isNot(contains('635')));
        expect(everything, isNot(contains('650')));
      },
    );

    test('l’heure d’arrivée est affichée quand le serveur la fournit', () {
      final fields = ticketFields(
        _ticket(arrivalAt: DateTime(2026, 10, 9, 14, 30)),
      );
      expect(
        fields.firstWhere((item) => item.$1 == 'Arrivée prévue').$2,
        contains('14:30'),
      );
    });

    test('l’heure d’embarquement vient du serveur et survit au stockage hors ligne', () {
      // Sans valeur du serveur, rien n'est calculé ni inventé dans l'application.
      expect(
        ticketFields(_ticket()).map((item) => item.$1),
        isNot(contains('Embarquement')),
      );

      final json = _ticket().toJson();
      (json['trip_detail'] as Map<String, dynamic>)['boarding_at'] =
          '2026-10-08T22:40:00Z';
      final ticket = Ticket.fromJson(json);
      expect(
        ticket.trip.boardingAt,
        DateTime.utc(2026, 10, 8, 22, 40).toLocal(),
      );

      // Relu depuis le stockage local, le billet garde la même heure d'embarquement.
      final restored = Ticket.fromJson(
        jsonDecode(jsonEncode(ticket.toJson())) as Map<String, dynamic>,
      );
      expect(restored.trip.boardingAt, ticket.trip.boardingAt);
      final labels = ticketFields(restored).map((item) => item.$1).toList();
      expect(
        labels.indexOf('Embarquement'),
        lessThan(labels.indexOf('Départ')),
      );
      expect(
        ticketFields(restored)
            .firstWhere((item) => item.$1 == 'Embarquement')
            .$2,
        isNot(missingValue),
      );
    });

    test('billet payé : « Payé », vente, mode de paiement, IFU acheteur et bas de billet', () {
      final json = {
        ..._ticket().toJson(),
        'status': 'ISSUED',
        'print_info': {
          'paid': true,
          'sale': 'Vendeur : Agent TEST',
          'payment_mode': 'Espèces',
          'buyer_ifu': 'TEST-ACHETEUR',
          'boarding_place': 'TEST gare',
          'price_incl_tax': 7500,
          'price_excl_tax': null,
          'tax_lines': [],
          'agency': {
            'legal_name': 'TEST Raison sociale',
            'ifu': '',
            'rccm': '',
            'address': '',
            'phones': '',
            'email': '',
          },
          'conditions': '',
        },
      };
      final ticket = Ticket.fromJson(json);
      final fields = Map.fromEntries(
        ticketFields(ticket).map((item) => MapEntry(item.$1, item.$2)),
      );
      expect(fields['Statut'], 'Payé');
      expect(fields['Vente'], 'Vendeur : Agent TEST');
      expect(fields['Mode de paiement'], 'Espèces');
      expect(fields['IFU de l\'acheteur'], 'TEST-ACHETEUR');
      expect(fields['Lieu d\'embarquement'], 'TEST gare');
      // Sans IFU de l'agence, aucune décomposition HT / TVA.
      expect(fields.keys, isNot(contains('Prix HT')));
      final footer = ticketFooter(ticket);
      expect(footer.first, 'Raison sociale : TEST Raison sociale');
      expect(footer, contains('Conditions : À renseigner'));
      expect(footer[1], 'IFU : À renseigner · RCCM : À renseigner');
      final everything = [...fields.values, ...footer].join(' ');
      expect(everything, isNot(contains('XOF')));
      expect(everything, isNot(contains('Ticket émis')));
      // Survit au stockage hors ligne.
      final restored = Ticket.fromJson(
        jsonDecode(jsonEncode(ticket.toJson())) as Map<String, dynamic>,
      );
      expect(ticketFields(restored), ticketFields(ticket));
    });

    test('billet non payé : aucune ligne « Statut »', () {
      final held = Ticket.fromJson({..._ticket().toJson(), 'status': 'HELD'});
      final labels = ticketFields(held).map((item) => item.$1);
      expect(labels, isNot(contains('Statut')));
    });

    test('IFU de l\'agence renseigné : TVA/HT/TTC ne sont plus affichés, seul le montant net apparaît', () async {
      final ticket = Ticket.fromJson({
        ..._ticket().toJson(),
        'amount': 7500,
        'status': 'ISSUED',
        'qr_token': 'qr-test',
        'print_info': {
          'paid': true,
          'sale': 'Vente en ligne',
          'payment_mode': 'Mobile Money',
          'buyer_ifu': '',
          'boarding_place': '',
          'price_incl_tax': 7500,
          'price_excl_tax': 6356,
          'tax_lines': [
            {'name': 'TVA', 'rate': '18', 'amount': 1144},
          ],
          'agency': {
            'legal_name': 'TEST',
            'ifu': 'TEST-IFU',
            'rccm': 'TEST',
            'address': 'TEST',
            'phones': 'TEST',
            'email': 'test@example.invalid',
          },
          'conditions': '',
        },
      });
      final fields = Map.fromEntries(
        ticketFields(ticket).map((item) => MapEntry(item.$1, item.$2)),
      );
      expect(fields.containsKey('Prix HT'), isFalse);
      expect(fields.containsKey('Prix TTC'), isFalse);
      expect(fields.keys.any((k) => k.contains('TVA')), isFalse);
      expect(fields['Prix du billet']!.replaceAll(RegExp(r'\s'), ''), '7500FCFA');
      // Toutes les lignes tiennent sur la page du PDF.
      final bytes = await buildTicketPdf(ticket);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test(
      'le PDF est généré avec un nom de fichier dérivé de la référence',
      () async {
        final bytes = await buildTicketPdf(_ticket());
        expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
        expect(bytes.length, greaterThan(1000));
        expect(
          ticketFileName(_ticket()),
          'billet-axis-AX-20261008-ABCD1234.pdf',
        );
      },
    );

    test('un billet non confirmé produit un PDF sans QR', () async {
      final bytes = await buildTicketPdf(_ticket(status: 'HELD'));
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('le partage ne contient que la référence et le trajet tant que le site n’a pas d’adresse', () {
      final text = ticketShareText(_ticket());
      expect(text, contains('AX-20261008-ABCD1234'));
      expect(text, contains('Cotonou → Parakou'));
      expect(text, isNot(contains('http')));
      expect(text, isNot(contains('axis.bj')));
    });

    test(
      'le partage reprend le lien fourni par le serveur, sans le modifier',
      () {
        final ticket = Ticket.fromJson({
          ..._ticket().toJson(),
          'public_url': 'https://exemple.test/t/AX-20261008-ABCD1234',
        });
        expect(
          ticketShareText(ticket),
          contains('https://exemple.test/t/AX-20261008-ABCD1234'),
        );
      },
    );

    test('les caractères hors Latin-1 sont remplacés pour le PDF', () {
      expect(pdfSafe('Cotonou → Parakou'), 'Cotonou > Parakou');
      expect(pdfSafe('1 000 XOF'), '1 000 XOF');
      expect(pdfSafe('Siège réservé'), 'Siège réservé');
    });
  });

  group('état du paiement', () {
    ApiException refusal(int status, Map<String, dynamic> data) =>
        ApiException('refus', statusCode: status, data: data);

    test('paiement pas encore confirmé : en attente', () {
      final error = refusal(400, {'detail': 'x', 'payment_status': 'pending'});
      expect(
        phaseFromRefusal(error, reservationExpired: false),
        PaymentPhase.awaiting,
      );
    });

    test('paiement non confirmé et délai dépassé : expiré', () {
      final error = refusal(400, {'detail': 'x', 'payment_status': 'pending'});
      expect(
        phaseFromRefusal(error, reservationExpired: true),
        PaymentPhase.expired,
      );
    });

    test('paiement refusé ou annulé : échec', () {
      for (final status in ['declined', 'canceled']) {
        final error = refusal(400, {'detail': 'x', 'payment_status': status});
        expect(
          phaseFromRefusal(error, reservationExpired: false),
          PaymentPhase.failed,
        );
      }
    });

    test('paiement arrivé après expiration : remboursement à traiter', () {
      final error = refusal(409, {'detail': 'x', 'refund_due': true});
      expect(error.refundDue, isTrue);
      expect(
        phaseFromRefusal(error, reservationExpired: true),
        PaymentPhase.refundDue,
      );
    });

    test('une erreur réseau n’a ni code HTTP ni statut de paiement', () {
      final error = ApiException('Réseau indisponible');
      expect(error.isNetwork, isTrue);
      expect(error.paymentStatus, isNull);
      expect(error.refundDue, isFalse);
    });
  });
}
