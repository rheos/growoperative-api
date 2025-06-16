#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails
rm -f /app/tmp/pids/server.pid

# Wait for database to be ready
bin/wait-for-db.sh ${DATABASE_HOST:-db}

# Setup database based on environment
if [ "$RAILS_ENV" = "development" ]; then
  bundle exec rails db:create
  bundle exec rails db:migrate
  bundle exec rails db:seed
else
  # In production, only run migrations
  bundle exec rails db:migrate
  # Only seed in production if explicitly requested
  if [ "$SEED_DATABASE" = "true" ]; then
    bundle exec rails db:seed
  fi
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile)
exec "$@" 