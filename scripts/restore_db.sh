#!/usr/bin/env bash
# Restore a Growoperative database from an S3 backup dump.
#
# Usage:
#   ./restore_db.sh growoperative_demo                    # latest dump
#   ./restore_db.sh growoperative_demo 2026-05-20T0917Z   # specific point in time
#
# DESTRUCTIVE: overwrites the target database. Prompts for confirmation.
# After restoring, run migrations if the dump predates recent schema changes:
#   docker exec <backend-container> bundle exec rails db:migrate

set -euo pipefail

CONF="${BACKUP_ENV:-/home/ubuntu/backups/backup.env}"
# shellcheck disable=SC1090
set -a; source "$CONF"; set +a

BUCKET="${BACKUP_BUCKET:-growoperative-backups}"
DB="${1:?usage: restore_db.sh <database> [timestamp]}"
TS="${2:-}"

if [ -z "$TS" ]; then
  KEY="$(aws s3 ls "s3://$BUCKET/$DB/" | sort | tail -1 | awk '{print $4}')"
  [ -n "$KEY" ] || { echo "no backups found for $DB"; exit 1; }
  SRC="s3://$BUCKET/$DB/$KEY"
else
  SRC="s3://$BUCKET/$DB/${TS}.sql.gz"
fi

echo "About to restore:"
echo "  source: $SRC"
echo "  target: $DB on $DB_HOST  (existing data will be overwritten)"
read -rp "Type the database name to confirm: " ACK
[ "$ACK" = "$DB" ] || { echo "aborted"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
aws s3 cp "$SRC" "$TMP/dump.sql.gz"
gunzip "$TMP/dump.sql.gz"
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB" < "$TMP/dump.sql"

echo "restore complete."
echo "If the dump predates recent migrations, run: rails db:migrate"
