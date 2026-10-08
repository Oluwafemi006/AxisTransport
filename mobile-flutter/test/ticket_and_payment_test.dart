import 'dart:convert';

import 'package:axis_transport_flutter/core/api_client.dart';
import 'package:axis_transport_flutter/core/models.dart';
import 'package:axis_transport_flutter/features/bookings/application/booking_checkout.dart';
import 'package:axis_transport_flutter/features/tickets/ticket_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Ticket _ticket({DateTime? arrivalAt, String passengerName = 'Awa Test', String status = 'ISSUED'}) => Ticket(
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
    test('les champs viennent du serveur et une donnée absente affiche « à confirmer »', () {
      final fields = Map.fromEntries(
        ticketFields(_ticket(passengerName: '  ')).map((item) => MapEntry(item.$1, item.$2)),
      );
      expect(fields['Référence'], 'AX-20261008-ABCD1234');
      expect(fields['Trajet'], 'Cotonou → Parakou');
      expect(fields['Siège'], '3A');
      expect(fields['Arrivée prévue'], missingValue);
      expect(fields['Passager'], missingValue);
      expect(fields['Départ'], contains('08:00'));
    });

    test('l’heure d’arrivée est affichée quand le serveur la fournit', () {
      final fields = ticketFields(_ticket(arrivalAt: DateTime(2026, 10, 9, 14, 30)));
      expect(fields.firstWhere((item) => item.$1 == 'Arrivée prévue').$2, contains('14:30'));
    });

    test('le PDF est généré avec un nom de fichier dérivé de la référence', () async {
      final bytes = await buildTicketPdf(_ticket());
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      expect(ticketFileName(_ticket()), 'billet-axis-AX-20261008-ABCD1234.pdf');
    });

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

    test('le partage reprend le lien fourni par le serveur, sans le modifier', () {
      final ticket = Ticket.fromJson({
        ..._ticket().toJson(),
        'public_url': 'https://exemple.test/t/AX-20261008-ABCD1234',
      });
      expect(ticketShareText(ticket), contains('https://exemple.test/t/AX-20261008-ABCD1234'));
    });

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
      expect(phaseFromRefusal(error, reservationExpired: false), PaymentPhase.awaiting);
    });

    test('paiement non confirmé et délai dépassé : expiré', () {
      final error = refusal(400, {'detail': 'x', 'payment_status': 'pending'});
      expect(phaseFromRefusal(error, reservationExpired: true), PaymentPhase.expired);
    });

    test('paiement refusé ou annulé : échec', () {
      for (final status in ['declined', 'canceled']) {
        final error = refusal(400, {'detail': 'x', 'payment_status': status});
        expect(phaseFromRefusal(error, reservationExpired: false), PaymentPhase.failed);
      }
    });

    test('paiement arrivé après expiration : remboursement à traiter', () {
      final error = refusal(409, {'detail': 'x', 'refund_due': true});
      expect(error.refundDue, isTrue);
      expect(phaseFromRefusal(error, reservationExpired: true), PaymentPhase.refundDue);
    });

    test('une erreur réseau n’a ni code HTTP ni statut de paiement', () {
      final error = ApiException('Réseau indisponible');
      expect(error.isNetwork, isTrue);
      expect(error.paymentStatus, isNull);
      expect(error.refundDue, isFalse);
    });
  });
}
