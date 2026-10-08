import 'dart:io';

class AppConfig {
  const AppConfig._();

  static String get apiUrl {
    const fromEnv = String.fromEnvironment('AXIS_API_URL');
    if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/$'), '');
    // Retourne l'IP Wi-Fi du PC. Le pare-feu est ouvert, donc le téléphone y accèdera directement via son point d'accès.
    if (Platform.isAndroid) return 'http://192.168.1.198:8000/api/v1';
    return 'http://127.0.0.1:8000/api/v1';
  }
}
