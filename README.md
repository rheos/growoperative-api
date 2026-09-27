# GrowOperative API

The Rails backend for GrowOperative, a local food exchange platform. It manages product listings, inventory, requests through supply chains, orders, and settlement. This repository contains the backend's development history, beginning in 2018.

The current stack is Ruby 3.4.11, Rails 8.1.4, and PostgreSQL 16. The web and mobile frontend lives in a separate repository. Shared identity and contacts come from FOAF auth; the FOAF credit service handles the shared ledger. This backend also contains older application-level trustline code and its documentation.

## Run locally

Install Docker with Docker Compose and OpenSSL. Run these commands from this repository:

```sh
cp .env.example .env
printf '\nSECRET_KEY_BASE=%s\n' "$(openssl rand -hex 64)" >> .env
docker compose up --build -d db backend
```

The API listens at `http://localhost:3001`. Check its database connection with:

```sh
curl --fail http://localhost:3001/v1/health
```

Startup prepares the local database from the current schema and seed data. Private database dumps are not needed. The bootstrap account is named `robin` for compatibility with the existing seed data. Set `SEED_ADMIN_PASSWORD` in `.env` before its first creation if you need a known local password; otherwise it receives a random password. Seeding does not reset an existing account's password.

The backend can boot on its own. Full login, contact, and credit flows require separately configured FOAF services and an application frontend. Set the FOAF auth URL and service token in your local `.env`; the credit service URL and feature flags are in `docker-compose.yml`. These point to local services by default.

The older React frontend is optional. If you have it checked out at `../platform` with its own environment file, start it with:

```sh
docker compose --profile legacy-frontend up -d frontend
```

## Run tests

Always set `RAILS_ENV=test`. The test suite clears its database, so running it with the development environment would destroy local development data.

```sh
docker compose exec -e RAILS_ENV=test backend bundle exec rails db:test:prepare
docker compose exec -e RAILS_ENV=test backend bin/test
```

Tests use `TEST_DATABASE_URL`, separate from `DATABASE_URL`. Both are configured for the local PostgreSQL container in `docker-compose.yml`.
`bin/test` also disables outgoing FOAF writes and replaces service URLs with container-local addresses so tests cannot inherit development-service connections.

The Python maintenance-script checks run in a separate container:

```sh
docker run --rm -v "$PWD:/app:ro" -w /app python:3.12-slim sh -c \
  'pip install -r scripts/requirements.txt && python scripts/test_trade_test.py && python scripts/test_foaf_reset_demo.py'
```

## Configuration

Keep credentials in your environment or hosting provider's secret store. `.env` files, SQL snapshots, and Rails credential keys are ignored by Git and excluded from Docker build context.

- `SECRET_KEY_BASE` supplies Rails signing material. Deployed environments must provide their own value.
- `DEVISE_SECRET_KEY` and `DEVISE_JWT_SECRET_KEY` override the corresponding Devise keys; otherwise they use the Rails secret.
- `DATABASE_URL` supplies the deployed PostgreSQL connection. Tests use `TEST_DATABASE_URL`.
- `FOAF_AUTH_BASE_URL` and `FOAF_AUTH_SERVICE_TOKEN` connect the backend to its FOAF auth tenant.
- S3 uploads use `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, and `AWS_S3_BUCKET`. Local development uses file storage when no bucket is set.

Changing signing keys can invalidate existing tokens. Set and coordinate deployed keys before changing authentication configuration.

## Documentation

The [documentation index](./doc/README.md) links to the domain model and API reference. The [mutual credit documentation](./doc/mutual_credit/README.md) describes the application-level trustline implementation retained here; it is not the specification for the separate FOAF credit service.

## License

A license has not yet been selected for this repository.
