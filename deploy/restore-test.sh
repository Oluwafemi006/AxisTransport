#!/bin/sh
# Test de restauration : restaure une sauvegarde dans une base À PART, compte quelques tables, puis la supprime.
# La base réelle n'est jamais touchée. Usage : deploy/restore-test.sh [fichier.dump]   (défaut : la plus récente)
set -eu

cd "${AXIS_DIR:-$HOME/axis}"
COMPOSE="${AXIS_COMPOSE:-docker compose --env-file .env.vps -f compose.vps.yaml}"
BACKUP_DIR="${AXIS_BACKUP_DIR:-$HOME/sauvegardes}"
TEST_DB="axis_essai_restauration"

dump="${1:-$(ls -1t "$BACKUP_DIR"/axis-*.dump 2>/dev/null | head -n 1)}"
if [ -z "$dump" ] || [ ! -s "$dump" ]; then
  echo "ÉCHEC : aucune sauvegarde trouvée dans $BACKUP_DIR." >&2
  exit 1
fi

cleanup() { $COMPOSE exec -T db dropdb -U axis --if-exists "$TEST_DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

cleanup
$COMPOSE exec -T db createdb -U axis "$TEST_DB"
$COMPOSE exec -T db pg_restore -U axis --no-owner -d "$TEST_DB" < "$dump"

echo "Sauvegarde restaurée à part : $dump"
for table in core_user core_ticket core_booking core_segmentfare core_paymentreceipt; do
  count=$($COMPOSE exec -T db psql -U axis -d "$TEST_DB" -tAc "select count(*) from $table;")
  echo "  $table : $count ligne(s)"
done
echo "Restauration réussie ; la base d'essai est supprimée."
