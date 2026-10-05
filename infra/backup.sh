#!/usr/bin/env bash
# Sauvegarde quotidienne des bases PostgreSQL (Fineract + Keycloak).
# Crontab : 30 2 * * * /opt/godafret/infra/backup.sh >> /var/log/godafret-backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"

DEST=${BACKUP_DIR:-/var/backups/godafret}
KEEP_DAYS=${KEEP_DAYS:-14}
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DEST"
chmod 700 "$DEST"

for db in fineract_tenants fineract_default keycloak; do
  docker compose exec -T postgres pg_dump -U postgres -Fc "$db" > "$DEST/${db}-${STAMP}.dump"
done

find "$DEST" -name '*.dump' -mtime +"$KEEP_DAYS" -delete
echo "$(date -Is) sauvegarde OK -> $DEST"
