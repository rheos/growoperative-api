#!/bin/bash
# wait-for-db.sh

set -e

host="$1"
shift
cmd="$@"

# Postgres tiers (Neon/Contabo) use DATABASE_URL and have no mysql client; Neon is
# always-up, so there is nothing to wait for. Skip straight to the command. MySQL
# prod/demo (no postgres DATABASE_URL) keep the original wait below.
case "${DATABASE_URL:-}" in
  postgres://*|postgresql://*)
    # entrypoint.prod.sh calls this as a readiness gate with no command, so exit
    # cleanly; if a command was passed, exec it (never fall through to mysql).
    [ -n "$cmd" ] && exec $cmd
    exit 0
    ;;
esac

until mysql --skip-ssl -h "$host" -u"$DATABASE_USERNAME" -p"$DATABASE_PASSWORD" -e 'SELECT 1'; do
  >&2 echo "MySQL is unavailable - sleeping"
  sleep 1
done

>&2 echo "MySQL is up - executing command"
exec $cmd 
