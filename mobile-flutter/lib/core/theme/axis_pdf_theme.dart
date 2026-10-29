import 'package:pdf/widgets.dart' as pw;

/// Styles typographiques réservés au générateur PDF de billet (`ticket_document.dart`).
///
/// Isolés dans `lib/core/theme/` afin qu'aucune taille de police ne soit codée en dur hors thème.
abstract final class AxisPdfTypography {
  static final pw.TextStyle brandTitle = pw.TextStyle(
    fontSize: 22,
    fontWeight: pw.FontWeight.bold,
  );

  static const pw.TextStyle subtitle = pw.TextStyle(fontSize: 12);

  static final pw.TextStyle fieldLabel = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    fontSize: 11,
  );

  static const pw.TextStyle fieldValue = pw.TextStyle(fontSize: 11);

  static const pw.TextStyle notice = pw.TextStyle(fontSize: 10);

  static const pw.TextStyle footer = pw.TextStyle(fontSize: 8);
}
