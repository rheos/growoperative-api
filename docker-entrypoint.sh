#!/bin/bash
set -e

if [ "$RAILS_ENV" = "production" ]; then
  exec ./entrypoint.prod.sh "$@"
else
  exec ./entrypoint.sh "$@"
fi 