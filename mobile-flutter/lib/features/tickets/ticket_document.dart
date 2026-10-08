import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/models.dart';

/// Texte affiché quand le serveur n'a pas fourni la donnée. Rien n'est inventé.
const missingValue = 'à confirmer';

String _orMissing(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? missingValue : text;
}

/// Les informations du billet, uniquement tirées de la réponse du serveur.
List<(String, String)> ticketFields(Ticket ticket) {
  final route = ticket.trip.route;
  final origin = route.origin?.name;
  final destination = route.destination?.name;
  return [
    ('Référence', _orMissing(ticket.reference)),
    (
      'Trajet',
      origin != null && destination != null
          ? '$origin → $destination'
          : _orMissing(route.label),
    ),
    ('Départ', formatFullDateTime(ticket.trip.departureAt)),
    (
      'Arrivée prévue',
      ticket.trip.arrivalAt == null
          ? missingValue
          : formatFullDateTime(ticket.trip.arrivalAt!),
    ),
    ('Siège', _orMissing(ticket.seat.number)),
    ('Passager', _orMissing(ticket.passengerName)),
    // Prix du billet seul (tarif) : les frais de paiement n'apparaissent jamais sur le billet.
    ('Prix du billet', formatMoney(ticket.amount, ticket.currency)),
    ('Statut', _orMissing(ticket.statusDisplay)),
  ];
}

/// Les polices PDF standard ne couvrent que le Latin-1 : on remplace les rares autres signes.
String pdfSafe(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x2192) {
      buffer.write('>');
    } else if (rune == 0x202F || rune == 0x00A0 || rune == 0x2009) {
      buffer.write(' ');
    } else if (rune == 0x2019) {
      buffer.write("'");
    } else if (rune <= 0xFF) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

String ticketFileName(Ticket ticket) =>
    'billet-axis-${ticket.reference.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.pdf';

/// Billet au format PDF : QR code et informations du serveur, rien d'autre.
Future<Uint8List> buildTicketPdf(Ticket ticket) {
  final document = pw.Document(title: pdfSafe('Billet ${ticket.reference}'));
  final fields = ticketFields(ticket);
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'AXIS Transport',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(pdfSafe('Billet électronique'), style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 18),
          if (ticket.isConfirmed && ticket.qrToken.isNotEmpty)
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: ticket.qrToken,
                width: 190,
                height: 190,
              ),
            )
          else
            pw.Text(pdfSafe('QR code : $missingValue')),
          pw.SizedBox(height: 18),
          for (final (label, value) in fields)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 105,
                    child: pw.Text(
                      pdfSafe(label),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(pdfSafe(value), style: const pw.TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          pw.Spacer(),
          pw.Text(
            pdfSafe('Présentez ce QR code à l\'embarquement.'),
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
  return document.save();
}

/// Message de partage : la référence et le trajet. Le lien n'apparaît que si le serveur
/// fournit l'adresse publique du site ; l'application n'en fabrique jamais.
String ticketShareText(Ticket ticket) {
  final route = ticketFields(ticket).firstWhere((item) => item.$1 == 'Trajet').$2;
  final lines = [
    'AXIS Transport',
    'Billet : ${ticket.reference}',
    'Trajet : $route',
    if (ticket.publicUrl.isNotEmpty) ...['', 'Consultez votre billet :', ticket.publicUrl],
  ];
  return lines.join('\n');
}
