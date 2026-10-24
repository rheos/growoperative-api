#!/usr/bin/env bash
# wait-for-db.sh

set -euo pipefail

host="${1:-db}"
if [[ $# -gt 0 ]]; then
  shift
fi
cmd=("$@")

wait_target=()
if [[ -n "${DATABASE_URL:-}" ]]; then
  wait_target=(-d "${DATABASE_URL}")
else
  wait_target=(-h "${host}" -U "${DATABASE_USERNAME:-postgres}" -d "${DATABASE_NAME:-postgres}")
fi

until pg_isready "${wait_target[@]}" >/dev/null 2>&1; do
  >&2 echo "PostgreSQL is unavailable - sleeping"
  sleep 1
done

>&2 echo "PostgreSQL is up"
if [[ ${#cmd[@]} -gt 0 ]]; then
  exec "${cmd[@]}"
fi
