import 'package:flutter/services.dart' show rootBundle;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/theme/axis_pdf_theme.dart';

/// Texte affiché quand une information obligatoire du billet manque. Rien n'est inventé.
const missingValue = 'À renseigner';

String _orMissing(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? missingValue : text;
}

/// Les lignes du billet, uniquement tirées de la réponse du serveur.
/// Une information facultative absente (arrivée, lieu d'embarquement, IFU…) est masquée.
List<(String, String)> ticketFields(Ticket ticket) {
  final info = ticket.printInfo;
  final origin = (info != null && info.origin.isNotEmpty)
      ? info.origin
      : ticket.originName ?? ticket.trip.route.origin?.name;
  final destination = (info != null && info.destination.isNotEmpty)
      ? info.destination
      : ticket.destinationName ?? ticket.trip.route.destination?.name;
  final label = (info != null && info.segmentLabel.isNotEmpty)
      ? info.segmentLabel
      : ticket.segmentLabel ?? (origin != null && destination != null ? '$origin → $destination' : ticket.trip.route.label);
  final depLabel = (info != null && info.departureLabel.isNotEmpty)
      ? info.departureLabel
      : ticket.departureLabel ?? 'Départ';
  final depTime = (info?.departureAt != null)
      ? info!.departureAt!
      : (ticket.effectiveDepartureAt ?? ticket.trip.departureAt);
  final boardingDisplay = (info != null && info.boardingDisplay.trim().isNotEmpty)
      ? info.boardingDisplay.trim()
      : (ticket.boardingDisplay?.trim() ?? '');
  final alightingDisplay = (info != null && info.alightingDisplay.trim().isNotEmpty)
      ? info.alightingDisplay.trim()
      : (ticket.alightingDisplay?.trim() ?? '');
  final paid = info?.paid ?? ticket.isConfirmed;
  return [
    ('Référence', _orMissing(ticket.reference)),
    ('Trajet', _orMissing(label)),
    if (boardingDisplay.isNotEmpty)
      ('Embarquement', boardingDisplay),
    if (alightingDisplay.isNotEmpty)
      ('Débarquement', alightingDisplay),
    if (info != null && info.boardingPlace.trim().isNotEmpty)
      ('Lieu d\'embarquement', info.boardingPlace.trim()),
    if (ticket.trip.boardingAt != null)
      (boardingDisplay.isNotEmpty ? 'Heure d\'embarquement' : 'Embarquement', formatFullDateTime(ticket.trip.boardingAt!)),
    (depLabel, formatFullDateTime(depTime)),
    if (ticket.trip.arrivalAt != null)
      ('Arrivée prévue', formatFullDateTime(ticket.trip.arrivalAt!)),
    ('Siège', _orMissing(ticket.seat.number)),
    ('Passager', _orMissing(ticket.passengerName)),
    // Prix net du billet : seul le montant net est affiché, aucune mention de TVA/HT/TTC.
    ('Prix du billet', formatMoney(ticket.amount, ticket.currency)),
    if (paid) ('Statut', 'Payé'),
    if (info != null && info.sale.isNotEmpty) ('Vente', info.sale),
    if (info != null && info.paymentMode.isNotEmpty)
      ('Mode de paiement', info.paymentMode),
    if (info != null && info.buyerIfu.trim().isNotEmpty)
      ('IFU de l\'acheteur', info.buyerIfu.trim()),
  ];
}

/// Bas du billet : agence (jamais les comptes bancaires) et conditions ; une ligne vide est masquée.
List<String> ticketFooter(Ticket ticket) => ticketFooterLines(ticket.printInfo);

/// Les polices PDF standard ne couvrent que le Latin-1 : on remplace les rares autres signes.
String pdfSafe(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x2192) {
      buffer.write('>');
    } else if (rune == 0x202F || rune == 0x00A0 || rune == 0x2009) {
      buffer.write(' ');
    } else if (rune == 0x2013 || rune == 0x2014) {
      buffer.write('-');
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
Future<Uint8List> buildTicketPdf(Ticket ticket) async {
  // Logo officiel ; s'il ne peut pas être chargé, le nom est écrit en texte.
  pw.MemoryImage? logo;
  try {
    final data = await rootBundle.load('assets/axis-logo-ticket.png');
    logo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    logo = null;
  }
  final document = pw.Document(
    title: pdfSafe('Billet de transport ${ticket.reference}'),
  );
  final fields = ticketFields(ticket);
  document.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(logo, height: 44),
            )
          else
            pw.Text(
              'AXIS Transport',
              style: AxisPdfTypography.brandTitle,
            ),
          pw.SizedBox(height: 4),
          pw.Text(
            pdfSafe('Billet de transport'),
            style: AxisPdfTypography.subtitle,
          ),
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
            pw.Text(pdfSafe('QR code disponible après le paiement.')),
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
                      style: AxisPdfTypography.fieldLabel,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      pdfSafe(value),
                      style: AxisPdfTypography.fieldValue,
                    ),
                  ),
                ],
              ),
            ),
          pw.Spacer(),
          pw.Text(
            pdfSafe('Présentez ce QR code à l\'embarquement.'),
            style: AxisPdfTypography.notice,
          ),
          pw.SizedBox(height: 8),
          for (final line in ticketFooter(ticket))
            pw.Text(pdfSafe(line), style: AxisPdfTypography.footer),
        ],
      ),
    ),
  );
  return document.save();
}

/// Message de partage : la référence et le trajet. Le lien n'apparaît que si le serveur
/// fournit l'adresse publique du site ; l'application n'en fabrique jamais.
String ticketShareText(Ticket ticket) {
  final route = ticketFields(ticket)
      .firstWhere((item) => item.$1 == 'Trajet')
      .$2;
  final lines = [
    'AXIS Transport',
    'Billet : ${ticket.reference}',
    'Trajet : $route',
    if (ticket.publicUrl.isNotEmpty) ...[
      '',
      'Consultez votre billet :',
      ticket.publicUrl,
    ],
  ];
  return lines.join('\n');
}
