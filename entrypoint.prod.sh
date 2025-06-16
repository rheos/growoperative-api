#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /app/tmp/pids/server.pid

# Setup database if needed
if [ "$RAILS_ENV" = "production" ]; then
  bundle exec rails db:migrate
  # Only seed in production if explicitly requested
  if [ "$SEED_DATABASE" = "true" ]; then
    bundle exec rails db:seed
  fi
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@" 