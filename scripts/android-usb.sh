#!/usr/bin/env bash
set -euo pipefail

if ! command -v adb >/dev/null 2>&1; then
  echo "ADB est absent. Installez android-tools-adb puis relancez ce script."
  exit 1
fi

device_count="$(adb devices | awk 'NR > 1 && $2 == "device" { count++ } END { print count+0 }')"
if [ "$device_count" -eq 0 ]; then
  echo "Aucun téléphone Android autorisé n’est détecté."
  echo "Activez Options pour les développeurs > Débogage USB, reconnectez le câble et acceptez l’empreinte RSA."
  exit 1
fi

adb reverse tcp:3000 tcp:3000
adb reverse tcp:8000 tcp:8000
adb reverse tcp:8081 tcp:8081

echo "Connexion USB prête. Ouvrez http://localhost:3000 dans Chrome sur le téléphone."
echo "L’API est transmise sur http://localhost:8000."
echo "Expo/Metro peut être ouvert avec exp://127.0.0.1:8081 lorsqu’il est démarré."
