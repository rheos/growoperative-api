#!/usr/bin/env bash
# Daily MySQL backup for Growoperative prod + demo.
#
# Runs on the Lightsail Rails host (35.163.185.37) via cron. Dumps each
# database, gzips it, and uploads to:
#     s3://growoperative-backups/<db>/<timestamp>.sql.gz
# Retention is handled server-side by the bucket's 30-day lifecycle rule,
# so this script never deletes anything (and its IAM creds can't).
#
# ── One-time host setup ──────────────────────────────────────────────
#   1. Deps:   sudo apt-get update && sudo apt-get install -y mysql-client awscli
#   2. Config: create /home/ubuntu/backups/backup.env  (chmod 600), e.g.
#        DB_HOST=172.26.13.168
#        DB_USER=buddy
#        DB_PASS=...
#        AWS_ACCESS_KEY_ID=...          # growoperative-upload-user
#        AWS_SECRET_ACCESS_KEY=...
#        AWS_DEFAULT_REGION=us-west-2
#   3. Cron (crontab -e):
#        17 9 * * *  /home/ubuntu/backups/backup_dbs.sh >> /home/ubuntu/backups/backup.log 2>&1
#      09:17 UTC ≈ 01:17 PT — off-peak and clear of the ~midnight MySQL CPU spike.

set -euo pipefail

CONF="${BACKUP_ENV:-/home/ubuntu/backups/backup.env}"
if [ ! -f "$CONF" ]; then
  echo "$(date -u +%FT%TZ) ERROR: config $CONF not found" >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a; source "$CONF"; set +a

BUCKET="${BACKUP_BUCKET:-growoperative-backups}"
DATABASES="${BACKUP_DATABASES:-growoperative_production growoperative_demo}"
TS="$(date -u +%Y-%m-%dT%H%MZ)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for DB in $DATABASES; do
  OUT="$TMP/${DB}_${TS}.sql.gz"
  echo "$(date -u +%FT%TZ) dumping $DB ..."
  mysqldump --single-transaction --quick --no-tablespaces --routines --triggers \
    -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB" | gzip -6 > "$OUT"
  SIZE="$(du -h "$OUT" | cut -f1)"
  aws s3 cp "$OUT" "s3://$BUCKET/${DB}/${TS}.sql.gz" --only-show-errors
  echo "$(date -u +%FT%TZ) uploaded s3://$BUCKET/${DB}/${TS}.sql.gz ($SIZE)"
done

echo "$(date -u +%FT%TZ) backup complete"
