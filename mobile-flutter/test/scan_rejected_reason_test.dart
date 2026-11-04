import 'package:axis_transport_flutter/core/theme/axis_theme.dart';
import 'package:axis_transport_flutter/core/widgets/scan_result_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Scan refusé : la raison exacte du serveur s’affiche, pas « Billet introuvable »', (tester) async {
    var again = false;
    await tester.pumpWidget(MaterialApp(
      theme: AxisTheme.light(),
      home: Scaffold(
        body: ScanResultSheet(
          data: const ScanResultData(
            type: ScanResultType.rejected,
            ticketNumber: 'AX-TEST',
            reason: "Le ticket n'est pas valable à la date du contrôle.",
          ),
          onPrimaryAction: () => again = true,
        ),
      ),
    ));
    expect(find.text('Billet refusé'), findsOneWidget);
    expect(find.text("Le ticket n'est pas valable à la date du contrôle."), findsOneWidget);
    expect(find.text('Billet introuvable'), findsNothing);
    await tester.tap(find.text('Scanner un autre billet'));
    expect(again, isTrue);
  });
}
