import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _fontsLoaded = false;

/// Police réelle de l'application (assets/fonts) : sans elle, flutter test mesure le texte avec sa police
/// de test, plus large, et signale de faux débordements.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  final loader = FontLoader('PlusJakartaSans');
  for (final weight in ['Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  }
  await loader.load();
  _fontsLoaded = true;
}

/// Largeurs de téléphone et échelles de texte auditées (texte agrandi dans les réglages du téléphone).
const auditWidths = [320.0, 360.0, 390.0];
const auditTextScales = [1.0, 1.3];

/// Affiche [build] à chaque largeur et échelle de texte et renvoie la liste des débordements
/// (« largeur × échelle : message »). Les autres erreurs sont relancées.
Future<List<String>> layoutOverflows(
  WidgetTester tester,
  Widget Function() build, {
  double height = 780,
  Future<void> Function(WidgetTester tester)? after,
  // Écran avec une animation ou un rafraîchissement continus : on avance le temps au lieu d'attendre la fin.
  bool settle = true,
}) async {
  final found = <String>[];
  await tester.runAsync(loadAppFonts);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  for (final width in auditWidths) {
    for (final scale in auditTextScales) {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      final previous = FlutterError.onError;
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(build());
        if (settle) {
          await tester.pumpAndSettle();
        } else {
          await tester.pump(const Duration(seconds: 2));
        }
        if (after != null) {
          await after(tester);
          await tester.pumpAndSettle();
        }
      } finally {
        FlutterError.onError = previous;
      }
      for (final error in errors) {
        final text = error.exceptionAsString();
        if (!text.contains('overflowed')) {
          FlutterError.reportError(error);
          continue;
        }
        final file = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(error.toString())?.group(0) ?? 'emplacement inconnu';
        found.add('${width.toInt()} × $scale : ${text.split('\n').first} ($file)');
      }
    }
  }
  return found.toSet().toList();
}
