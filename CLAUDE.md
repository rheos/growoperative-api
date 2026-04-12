# CLAUDE.md — Rails Backend

API server for Growoperative. Serves both the current web frontend and the new React Native app.

## Docker Commands

Run from `railsbackend/` directory:

```bash
docker-compose up                             # Start all services
docker-compose exec backend bash              # Shell access
docker-compose exec backend rails db:migrate  # Run migrations
docker-compose exec backend rails db:seed     # Seed database
docker-compose exec backend bundle exec rspec # Run tests
docker-compose logs backend                   # View logs
```

**Never run local rails/bundle commands.**

## Tech Stack

- Rails 5.2 API mode
- MySQL 8.0
- JWT authentication (HS256, 1-year expiry)
- CarrierWave + S3 for file uploads
- Devise for user management
- RSpec + Factory Bot for testing

## API

- **Base path:** `/api/v1/` (internally), served as `/v1/` (externally)
- **Auth:** JWT in HTTP-only cookie (`jwt`) or `Authorization: Bearer <token>` header
- **Auth key:** `user_name` (not email — email is optional)
- **CORS origins:** `localhost:3000`, `10.0.1.6:3000`, `beta.growoperative.app`

## Key Models

| Model | Purpose |
|-------|---------|
| User | Core entity, has roles via UserGroup, trustlines, items, relationships |
| Item | Product listing with category, grade, unit, images |
| ItemRequest | Request/reserve/ship workflow between users |
| Order | Groups multiple item requests |
| Relationship | Social connection between users with pricing |
| Invitation | Invite codes for new user registration |
| Category | Product classification |
| Grade | Quality level (A, B, C) |
| Trustline | Bilateral credit relationship (user_a, user_b, limits, balance) |
| TrustlineTransaction | Audit trail for all credit movements |
| UserCategoryPrice | Per-user category pricing overrides |
| UserRelationshipPrice | Per-relationship pricing |
| CategorySize | Pack size limits per user per category |
| JWTBlacklist | Revoked token storage |

## Authentication

### JWT Generation (`lib/jwt/jwt_generation_service.rb`)

- Algorithm: HS256 with `SECRET_KEY_BASE`
- Payload: `{ iat, exp (1 year), sub: { user_id }, jti (UUID) }`
- Token set in signed httpOnly cookie AND returned in response body

### JWT Validation (`lib/jwt/jwt_decoding_service.rb`)

- Checks signature, expiration, algorithm
- `current_user` reads from cookie first, falls back to Authorization header

### Session Controller (`app/controllers/api/v1/sessions_controller.rb`)

- `POST /v1/sessions` — login (skips auth)
- `GET /v1/sessions` — current session check
- `DELETE /v1/sessions` — logout (blacklists jti)

### Auth Middleware (`app/controllers/api/v1/api_controller.rb`)

- `before_action :authenticate!` on all actions by default
- Skipped on: sessions#create, registrations#create

## Common Tasks

### Adding an API Endpoint

1. Create controller in `app/controllers/api/v1/`
2. Add route in `config/routes.rb`
3. Add serializer if needed
4. Write RSpec tests

### Database Changes

```bash
docker-compose exec backend rails generate migration AddFieldToModel field:type
docker-compose exec backend rails db:migrate
```

### Dev Data Snapshots

MySQL dumps live in `db/snapshots/`. Used to save/restore a known-good dev database state with realistic test data (users, items, requests, orders).

```bash
# Save
docker-compose exec db sh -c 'mysqldump -u root -p"rDKftaN-64" growoperative_development 2>/dev/null' > db/snapshots/dev_preshipment.sql

# Restore
docker-compose exec db sh -c 'mysql -u root -p"rDKftaN-64" growoperative_development 2>/dev/null' < db/snapshots/dev_preshipment.sql
```

Current snapshot: `dev_preshipment.sql` — full demo network with requests and orders, pre-shipment state (no credit transactions yet).

## Deployment

- **Server:** AWS Lightsail `growoperative-rails` (`35.163.185.37`)
- **Deploy:** GitHub Actions → SSH → git pull → Docker rebuild
- **URL:** `https://api.growoperative.app`
- **SSL:** Certbot
