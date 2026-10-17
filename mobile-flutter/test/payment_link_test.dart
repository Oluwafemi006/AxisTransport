import 'package:axis_transport_flutter/shared/payment_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final url = Uri.parse('https://process.fedapay.com/paiement-test');

  Future<(bool, List<LaunchMode>)> open({
    required bool customTabs,
    Set<LaunchMode> failing = const {},
  }) async {
    final calls = <LaunchMode>[];
    final opened = await openPaymentPage(
      url,
      supports: (mode) async =>
          customTabs && mode == LaunchMode.inAppBrowserView,
      launcher: (target, {mode = LaunchMode.platformDefault}) async {
        expect(target, url);
        calls.add(mode);
        return !failing.contains(mode);
      },
    );
    return (opened, calls);
  }

  test('paiement ouvert dans un onglet Chrome intégré, sans quitter l\'application', () async {
    final (opened, calls) = await open(customTabs: true);
    expect(opened, isTrue);
    expect(calls, [LaunchMode.inAppBrowserView]);
  });

  test(
    'sans onglet intégré possible : navigateur externe, jamais de WebView',
    () async {
      final (opened, calls) = await open(customTabs: false);
      expect(opened, isTrue);
      expect(calls, [LaunchMode.externalApplication]);
      expect(calls, isNot(contains(LaunchMode.inAppWebView)));
    },
  );

  test(
    'échec de l\'onglet intégré : repli sur le navigateur externe',
    () async {
      final (opened, calls) = await open(
        customTabs: true,
        failing: {LaunchMode.inAppBrowserView},
      );
      expect(opened, isTrue);
      expect(calls, [
        LaunchMode.inAppBrowserView,
        LaunchMode.externalApplication,
      ]);
    },
  );

  test('aucun navigateur : échec signalé à l\'écran', () async {
    final (opened, _) = await open(
      customTabs: false,
      failing: {LaunchMode.externalApplication},
    );
    expect(opened, isFalse);
  });
}
