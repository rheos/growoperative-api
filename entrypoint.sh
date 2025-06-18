#!/bin/bash
set -e

# Clean up stale server.pid
rm -f /app/tmp/pids/server.pid

# Wait for the DB to be reachable
if [ -f ./bin/wait-for-db.sh ]; then
  ./bin/wait-for-db.sh "${DATABASE_HOST:-db}"
fi

# Safe DB init for development
if [ "$RAILS_ENV" = "development" ]; then
  echo "🔍 Checking for existing database..."
  if ! bundle exec rails db:version >/dev/null 2>&1; then
    echo "📦 Database not found — creating and migrating..."
    bundle exec rails db:create db:migrate
    if [ "$SEED_DATABASE" = "true" ]; then
      echo "🌱 Seeding database..."
      bundle exec rails db:seed
    fi
  else
    echo "✅ Database exists — skipping creation"
  fi
else
  echo "🔧 Running production DB setup..."
  bundle exec rails db:migrate
  if [ "$SEED_DATABASE" = "true" ]; then
    bundle exec rails db:seed
  fi
fi

# Start the Rails server
echo "🚀 Starting Rails on port ${PORT:-3000}"
exec bundle exec rails server -b 0.0.0.0 -p "${PORT:-3000}"
