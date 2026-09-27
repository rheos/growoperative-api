#!/bin/bash
set -e

# Clean up stale server.pid
rm -f /app/tmp/pids/server.pid

# Wait for the DB to be reachable
if [ -f ./bin/wait-for-db.sh ]; then
  ./bin/wait-for-db.sh "${DATABASE_HOST:-db}"
fi

# On a fresh checkout, load the current schema instead of replaying legacy
# MySQL-era migrations. Existing databases receive pending migrations.
bundle exec rails db:prepare

# Only seed if SEED_DATABASE=true
if [ "$SEED_DATABASE" = "true" ]; then
  if ! bundle exec rails runner "exit User.any? ? 0 : 1"; then
    echo "🌱 Seeding database (no users found)..."
    bundle exec rails db:seed
  else
    echo "✅ Users exist — skipping db:seed"
  fi
fi

# Start the Rails server
echo "🚀 Starting Rails on port ${PORT:-3000}"
exec bundle exec rails server -b 0.0.0.0 -p "${PORT:-3000}"
