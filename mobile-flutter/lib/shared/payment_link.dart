import 'package:url_launcher/url_launcher.dart';

typedef LinkLauncher = Future<bool> Function(Uri url, {LaunchMode mode});
typedef ModeSupport = Future<bool> Function(LaunchMode mode);

Future<bool> _launch(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) =>
    launchUrl(url, mode: mode);

/// Ouvre la page de paiement Mobile Money sans quitter l'application : onglet Chrome intégré
/// (Custom Tab), avec l'adresse et le cadenas visibles. Jamais de WebView pour un paiement :
/// si le téléphone n'a pas de navigateur compatible, la page s'ouvre dans le navigateur, comme avant.
Future<bool> openPaymentPage(
  Uri url, {
  LinkLauncher launcher = _launch,
  ModeSupport supports = supportsLaunchMode,
}) async {
  if (await supports(LaunchMode.inAppBrowserView)) {
    if (await launcher(url, mode: LaunchMode.inAppBrowserView)) return true;
  }
  return launcher(url, mode: LaunchMode.externalApplication);
}
