import 'package:axis_transport_flutter/features/sold/sold_ticket.dart';
import 'package:flutter_test/flutter_test.dart';

SoldTicket _ticket(String phone, {String url = 'https://site.test/t/AX-TEST-1'}) => SoldTicket(
  reference: 'AX-TEST-1',
  route: 'Parakou → Cotonou',
  seat: '1',
  passengerName: 'Passager TEST',
  passengerPhone: phone,
  amountFcfa: 7500,
  statusDisplay: 'Ticket émis',
  soldAt: null,
  soldByName: '',
  publicUrl: url,
);

void main() {
  test('numéro international : WhatsApp s’ouvre sur le passager, message et lien préremplis', () {
    final uri = whatsappTicketUri(_ticket('+229 01 00 00 00 00'));
    expect(uri.host, 'wa.me');
    expect(uri.path, '/2290100000000');
    expect(uri.queryParameters['text'], contains('https://site.test/t/AX-TEST-1'));
  });

  test('numéro local : aucun indicatif deviné, WhatsApp fait choisir le contact', () {
    final uri = whatsappTicketUri(_ticket('97000000'));
    expect(uri.path, '/');
    expect(uri.queryParameters['text'], contains('AX-TEST-1'));
  });

  test('montant affiché en FCFA', () {
    expect(formatFcfa(7500), '7 500 FCFA');
  });
}
