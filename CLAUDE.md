# CLAUDE.md — Rails Backend

API server for Growoperative. Serves both the current web frontend and the new React Native app.

## Docker Commands

Run from `railsbackend/` directory:

```bash
docker-compose up                                                  # Start all services (db, backend, frontend)
docker-compose exec backend bash                                   # Shell access
docker-compose exec backend rails db:migrate                       # Run migrations
docker-compose exec backend rails db:seed                          # Seed database
docker-compose exec -e RAILS_ENV=test backend bundle exec rspec    # Run tests
docker-compose logs backend                                        # View logs
```

**CRITICAL: Always pass `-e RAILS_ENV=test` when running rspec.** The Docker container sets `RAILS_ENV=development` by default, and `rails_helper.rb` uses `||=` which won't override it. Without this flag, DatabaseCleaner will **wipe the development database**.

**Never run local rails/bundle commands.**

Port mapping: Rails container listens on 8080 internally, exposed as `localhost:3001`.

## Tech Stack

- Rails 5.2 API mode
- MySQL 5.7
- Puma (clustered, `WEB_CONCURRENCY` workers)
- JWT authentication (HS256, 1-year expiry)
- CarrierWave + fog-aws for S3 uploads (rmagick for image processing)
- Devise (username-based auth) + devise-jwt + devise_invitable
- fast_jsonapi for serialization
- RSpec + Factory Bot for testing

## API

- **Base path:** `/api/v1/` (internally), served as `/v1/` (externally)
- **Auth:** JWT in HTTP-only cookie (`jwt`) or `Authorization: Bearer <token>` header
- **Auth key:** `user_name` (not email — email is optional)
- **CORS origins:** `ENV['FRONTEND_URL']` (default `localhost:3000`), `localhost:8081`, `localhost:19006`, `10.0.1.6:3000`, `beta.growoperative.app`, `legacy.growoperative.app`
- **Credentials:** enabled (cookies sent cross-origin)

## Key Models

| Model | Purpose |
|-------|---------|
| User | Core entity, has roles via UserGroup, trustlines, items, relationships |
| UserGroup | Role assignments (admin, producer, broker, wholesaler, retailer, consumer, demo, superuser) |
| Item | Product listing with category, grade, unit, images |
| Inventory | Per-user copy of item; statuses: unavailable/available/reserved/in_order. `ref_id` links reserved copies back to original |
| ItemRequest | One hop in a supply chain step; statuses: pending → reserved → shipped → signed |
| RequestContract | Multi-hop supply chain path; has `steps` count and `current_step` pointer. Links ItemRequests together |
| Order | Groups item requests between same buyer-seller pair; statuses: pending → shipped → signed |
| Relationship | Directional social connection between users with pricing state |
| Invitation | Invite codes with chain depth tracking |
| Category | Product classification |
| Grade | Quality level (A, B, C) |
| Trustline | Bilateral credit (user_a_id < user_b_id enforced). Has two independent limits + balance |
| TrustlineTransaction | Audit trail for all credit movements (never deleted; reversals create counteracting records) |
| PendingPayment | App-level payment confirmation — recipient must confirm before trustline executes |
| UserCategoryPrice | Per-user category pricing overrides |
| UserRelationshipPrice | Per-relationship pricing (includes `receiving_price` for reverse direction) |
| CategorySize | Pack size limits per user per category |
| GlobalSetting | System-wide config (e.g., ChainLimit for max payment hops) |
| JWTBlacklist | Revoked token storage (jti-based) |

## Business Logic

### Pricing Hierarchy

Evaluated in order: **ItemPrice** (base) → **UserCategoryPrice** (user-level override per category) → **UserRelationshipPrice** (relationship-specific override). Pricing logic lives in helpers (`get_relation_price`), not controllers.

### Multi-Hop Item Requests

When a buyer requests an item, the system traces a path through relationships (BFS, max depth configurable via GlobalSetting). For each hop, a separate ItemRequest is created under a shared RequestContract. Path is calculated at request time and stored — not recalculated during acceptance.

On acceptance: a reserved Inventory is created (with `ref_id` pointing to original), quantity is decremented from the source, and an Order is auto-created/linked for that buyer-seller pair.

### Trustline Balance Math

- Balance is from user_a's perspective: positive = A owes B, negative = B owes A
- A pays B: `balance += amount`; B pays A: `balance -= amount`
- Available credit: `limit - max(balance_toward_creditor, 0)`

### Order Settlement

Settlement is negotiated, not automatic:
1. Shipper proposes settlement type (cash or credit)
2. Receiver agrees, offers cash, or counters with credit
3. Cash: payer records amount → payee confirms receipt → settled
4. Credit: both agree → `execute_credit_payment!` runs atomically (can auto-expand trustline limits if needed)

### Demo System

- Passwordless login for demo users via `POST /v1/demo/login`
- `DemoResetService` clears transactional data and restores from snapshot JSON
- S3 images are NOT deleted during demo resets (shared across resets via `skip_callback`)
- `GlobalSetting.demo_setup_enabled` gates one-time setup endpoint
- Core demo usernames are hardcoded in the DemoController

Rake tasks: `demo:mark_users`, `demo:snapshot`, `demo:reset`, `user:update_password`

## Authentication

### JWT Generation (`lib/jwt/jwt_generation_service.rb`)

- Algorithm: HS256 bridge tokens with `SECRET_KEY_BASE` until auth.foaf.io RS256 fully owns issuance
- Payload: `{ sub: foaf_id, aud: "growoperative", legacy_uid, iat, exp, jti }`
- Token returned in the response body only. Legacy `jwt` cookies are cleared, not minted.

### JWT Validation (`lib/jwt/jwt_decoding_service.rb`)

- Checks signature, expiration, algorithm, audience, JWKS, and revocation snapshot where applicable
- `current_user` reads Bearer tokens from the `Authorization` header only
- HS256 bridge handling is controlled by `FOAF_AUTH_HS256_BRIDGE_ENABLED`

### Session Controller (`app/controllers/api/v1/sessions_controller.rb`)

- `POST /v1/sessions` — login (skips auth)
- `GET /v1/sessions` — current session check
- `DELETE /v1/sessions` — logout (blacklists jti)

### Auth Middleware (`app/controllers/api/v1/api_controller.rb`)

- `before_action :authenticate!` on all actions by default
- Skipped on: sessions#create, registrations#create, home#index/verify, demo#login, debug#*, resources#*
- No self-service password reset — `ChangePasswordsController` is admin-only

## Key Controllers (Non-Obvious Patterns)

| Controller | Notes |
|---|---|
| ItemsController | Complex `index` with multi-hop relationship traversal (`range_degree` 0-3); recursive `all_items()` for network pricing |
| ItemRequestsController | BFS path-finding at request time (MAX_DEPTH=5); creates RequestContract + ItemRequest chain |
| TrustlinesController | Perspective-aware serialization (flips balance/limits based on which user is viewing) |
| PendingPaymentsController | Authorization enforces sender-or-receiver only |
| OrdersController | Settlement negotiation via `apply_action` state machine |
| DebugController | **Unauthenticated** — exposes order/request/user inspection queries |
| ResourcesController | Serves files from `/private/` directory |
| GlobalSettingsController | Admin-only; currently manages ChainLimit setting |

## Domain Constraints

- Demo users cannot have trustlines or relationships with non-demo users (model-level validation)
- Users cannot request their own items
- Consumer/retailer roles are filtered out of supply chain path calculations
- Invitation system tracks chain depth to prevent infinite user trees
- Inventory unit conversion: requests can specify different units than inventory, system converts via ItemUnit equivalence

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
- **Two backend containers, one repo:** `backend` (production, `.env.production`, prod MySQL DB) and `backend-demo` (demo + beta soak, `.env.demo`, demo MySQL DB). Both build from the same code on master.
- **Demo doubles as beta:** push to `master` → auto-deploys to `backend-demo` only (`demo.growoperative.app`). Soak there, then promote to prod manually.
- **Deploy workflows:**
  - `.github/workflows/deploy-demo.yml` — auto on push to master, builds & deploys `backend-demo`.
  - `.github/workflows/deploy-prod.yml` — manual `workflow_dispatch`, requires typing `deploy-prod` to confirm. Optional SHA input for rolling back. Deploys `backend`.
- **No tests in CI pipeline** — soak-time on demo is the safety net.
- **Production Docker:** `docker-compose.prod.yml` (no MySQL — connects to Lightsail DB at `172.26.13.168`)
- **Nginx:** reverse proxy with Certbot SSL. Box is API-only for GrowOperative since the 2026-05-27 frontend migration to Cloudflare Pages.
  - `api.growoperative.app` → `backend` (prod API)
  - `dpi.growoperative.app` → `backend-demo` (demo API; added during the Cloudflare migration so the CF demo/beta frontends have a demo backend host separate from their own host)
  - Other hosts on this nginx: `api.foaf.io`, `dpi.foaf.io`, `auth.foaf.io`, `dauth.foaf.io`.
  - The old static-frontend server blocks for `growoperative.app` / `demo.growoperative.app` / `beta.growoperative.app` still exist in `nginx.conf` but are unused (DNS for all three points at Cloudflare Pages). Safe to remove for tidiness; harmless to leave.
- **Frontend dist mounts:** previously `/home/ubuntu/growoperative-app/dist-prod` + `dist-demo` were bound to `/var/www/prod` + `/var/www/demo`. **Unused** after the migration — DNS no longer resolves there. The `growoperative-app` repo's `deploy-demo.yml` / `deploy-prod.yml` workflows that populated them have been deleted; Cloudflare Pages now builds and serves the frontends directly from `main` (web + demo) and `develop` (beta).
- **URLs:** prod API `https://api.growoperative.app`; demo API `https://dpi.growoperative.app` (was `https://demo.growoperative.app/v1/` pre-migration — the app's `apiBase.ts` now points demo at `dpi`). Web frontends: `https://web.growoperative.app` (prod), `https://demo.growoperative.app` (demo), `https://beta.growoperative.app` (soak/develop); all Cloudflare Pages.

## Key Environment Variables

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | JWT signing + Rails secrets (changing it invalidates all tokens) |
| `COOKIE_DOMAIN` | JWT cookie scope (`localhost` dev, `.growoperative.app` prod) |
| `FRONTEND_URL` | Primary CORS origin |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_S3_BUCKET` | CarrierWave S3 storage |
| `DATABASE_HOST`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` | MySQL connection |
| `SEED_DATABASE` | If `"true"`, auto-seeds DB on container startup (dev only) |
