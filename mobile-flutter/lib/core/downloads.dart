import 'package:flutter/services.dart';

const _channel = MethodChannel('axis/downloads');

/// Enregistre un fichier dans le dossier Téléchargements du téléphone (Android 10+).
/// Renvoie l'emplacement lisible par l'utilisateur. Lève une exception si l'appareil ne le permet pas.
Future<String> saveToDownloads({
  required String name,
  required Uint8List bytes,
  String mime = 'application/pdf',
}) async {
  final location = await _channel.invokeMethod<String>('save', {
    'name': name,
    'bytes': bytes,
    'mime': mime,
  });
  return location ?? name;
}
