#!/bin/bash
set -e

# Clean up old PID file
rm -f /app/tmp/pids/server.pid

# Wait for DB (optional, but smart if you have the script)
if [ -f ./bin/wait-for-db.sh ]; then
  ./bin/wait-for-db.sh "${DATABASE_HOST:-db}"
fi

# Run prod DB setup
if [ "$RAILS_ENV" = "production" ]; then
  echo "📦 Migrating DB..."
  bundle exec rails db:migrate

  if [ "$SEED_DATABASE" = "true" ]; then
    echo "🌱 Seeding DB..."
    bundle exec rails db:seed
  fi
fi

# ✅ Fallback if CMD is not passed (Fly does this sometimes!)
if [ "$#" -eq 0 ]; then
  echo "🚀 No CMD passed. Launching Rails manually..."
  exec bundle exec rails server -b 0.0.0.0 -p "${PORT:-8080}"
else
  echo "🎯 CMD passed. Executing: $@"
  exec "$@"
fi
