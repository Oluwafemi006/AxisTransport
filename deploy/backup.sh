#!/bin/sh
# Sauvegarde quotidienne de la base (pg_dump, format personnalisé) avec rotation. Voir DEPLOY.md, section 5.6.
# Sur le VPS : lancé par cron chaque nuit depuis ~/axis. Ne contient aucun secret : le mot de passe reste dans .env.vps.
set -eu

cd "${AXIS_DIR:-$HOME/axis}"
COMPOSE="${AXIS_COMPOSE:-docker compose --env-file .env.vps -f compose.vps.yaml}"
DB_NAME="${AXIS_DB_NAME:-axis}"
BACKUP_DIR="${AXIS_BACKUP_DIR:-$HOME/sauvegardes}"
KEEP_DAYS="${AXIS_BACKUP_KEEP_DAYS:-14}"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
target="$BACKUP_DIR/axis-$(date +%F-%H%M).dump"
partial="$target.partiel"

# Écrit d'abord dans un fichier temporaire : une sauvegarde interrompue ne remplace jamais une bonne.
$COMPOSE exec -T db pg_dump -U axis -Fc "$DB_NAME" > "$partial"
if [ ! -s "$partial" ]; then
  rm -f "$partial"
  echo "ÉCHEC : sauvegarde vide." >&2
  exit 1
fi
mv "$partial" "$target"
chmod 600 "$target"

# Rotation : supprime les sauvegardes de plus de KEEP_DAYS jours, jamais la plus récente.
find "$BACKUP_DIR" -name 'axis-*.dump' -mtime +"$KEEP_DAYS" ! -path "$target" -delete
echo "Sauvegarde : $target ($(du -h "$target" | cut -f1))"
