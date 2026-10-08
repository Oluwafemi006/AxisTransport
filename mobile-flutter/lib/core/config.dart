class AppConfig {
  const AppConfig._();

  static String get apiUrl {
    const fromEnv = String.fromEnvironment('AXIS_API_URL');
    if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');
    // Par défaut : tunnel USB (adb reverse tcp:8000 tcp:8000). Aucune adresse de réseau local
    // n'est codée ici : en Wi-Fi, passer --dart-define=AXIS_API_URL (voir scripts/flutter-wifi.sh).
    return 'http://127.0.0.1:8000/api/v1';
  }
}
