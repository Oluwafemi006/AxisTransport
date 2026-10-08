#!/usr/bin/env bash
set -euo pipefail

workspace_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-build}"
device_id="${2:-}"

case "$mode" in
  build) ;;
  run)
    if [ -z "$device_id" ]; then
      echo "Usage : ./scripts/flutter-wifi.sh run <identifiant-adb>"
      exit 1
    fi
    ;;
  *)
    echo "Mode inconnu : $mode. Utilisez build ou run."
    exit 1
    ;;
esac

for required_command in ip docker flutter curl; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "Commande absente : $required_command. Installez-la puis relancez ce script."
    exit 1
  fi
done

lan_ip="${AXIS_LAN_IP:-$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }')}"
if [ -z "$lan_ip" ]; then
  echo "Impossible de détecter l’adresse réseau de l’ordinateur."
  echo "Relancez avec AXIS_LAN_IP=<adresse-ip> ./scripts/flutter-wifi.sh $mode"
  exit 1
fi

if ! ip -4 -o addr show | awk '{ print $4 }' | cut -d/ -f1 | grep -Fxq "$lan_ip"; then
  echo "L’adresse $lan_ip n’est pas attribuée à cet ordinateur."
  exit 1
fi

echo "Backend Axis Transport : http://$lan_ip:8000/api/v1"
AXIS_LAN_IP="$lan_ip" docker compose -f "$workspace_dir/compose.yaml" --project-directory "$workspace_dir" up -d db backend

api_ready=false
for attempt in {1..45}; do
  if curl --noproxy '*' --silent --fail --max-time 3 --output /dev/null "http://$lan_ip:8000/api/v1/locations/"; then
    api_ready=true
    break
  fi
  sleep 2
done

if [ "$api_ready" != true ]; then
  echo "L’API ne répond pas sur http://$lan_ip:8000. Vérifiez Docker, le pare-feu et le réseau."
  exit 1
fi

echo "API vérifiée : http://$lan_ip:8000/api/v1/locations/"

cd "$workspace_dir/mobile-flutter"
flutter pub get

case "$mode" in
  build)
    apk_path="$workspace_dir/mobile-flutter/build/app/outputs/flutter-apk/app-debug.apk"
    if ! flutter build apk --debug --dart-define="AXIS_API_URL=http://$lan_ip:8000/api/v1"; then
      echo "La compilation de l’APK Wi-Fi n’a pas abouti. L’ancien APK éventuel n’a pas été actualisé."
      exit 1
    fi
    if [ ! -f "$apk_path" ]; then
      echo "Compilation terminée mais APK introuvable : $apk_path"
      exit 1
    fi
    echo "APK Wi-Fi prêt : $apk_path"
    ;;
  run)
    flutter run -d "$device_id" --dart-define="AXIS_API_URL=http://$lan_ip:8000/api/v1"
    ;;
esac
