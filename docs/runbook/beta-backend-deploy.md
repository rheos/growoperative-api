# Beta backend deploy runbook (bpi.growoperative.app + bauth.foaf.io)

**Status:** initial bring-up. **Shape:** isolated, lean, on-demand (decided 2026-06-24).

Gives `beta.growoperative.app` (Cloudflare Pages, builds `develop`) its own
backend instead of sharing demo's — so `develop` can be exercised against a
fresh app DB + auth without touching the live demo. Mirrors the dpi/dauth
split, but deliberately leaner and not always-on.

## What beta is (and isn't)

- **Own app DB:** `growoperative_beta`. **Own auth DB + issuer:** `foaf_auth_beta`,
  `iss=bauth.foaf.io`. Fully walled off from demo so resets don't cross-contaminate.
- **Lean:** beta auth has **no dedicated Sidekiq worker** and **no own Redis** —
  it points `REDIS_URL` at the existing `redis-demo` on **DB index 1**. Periodic
  auth-maintenance jobs simply don't run during a test session (harmless).
- **On-demand:** both containers sit behind the `beta` compose profile with
  `restart: "no"`. A normal `up -d` / reboot never starts them. Bring up only
  when testing: `bin/beta-up`; tear down: `bin/beta-down`. While down, nginx
  serves the maintenance page for bpi/bauth (the vhosts use a runtime docker
  resolver, NOT a static upstream, so nginx loads fine when beta is absent).
- **No FOAF publishing:** beta's mutual-credit lives entirely in `growoperative_beta`;
  there's no `foaf-beta` protocol container. (Add later if beta needs the FOAF mirror.)

Footprint when up: ~230 MiB (1-worker backend-beta + auth-beta). Idle: 0.

## Topology delta vs. today

```
nginx (railsbackend compose)
  + bpi.growoperative.app  -> backend-beta:8080   (runtime resolver, on-demand)
  + bauth.foaf.io          -> auth-beta:3000       (runtime resolver, on-demand)
railsbackend compose
  + backend-beta   (profile: beta, restart: no, .env.beta -> growoperative_beta)
foaf-auth compose
  + auth-beta      (profile: beta, restart: no, .env.beta -> foaf_auth_beta,
                    REDIS_URL=redis://redis-demo:6379/1)
growoperative-mysql box (172.26.13.168)
  + growoperative_beta  (user: growoperative_beta)
  + foaf_auth_beta      (user: foaf_auth_beta)
```

## Code already staged in the repos (this changeset)

- `railsbackend/docker-compose.prod.yml` — `backend-beta` service
- `railsbackend/nginx/nginx.conf` — bpi + bauth server blocks (runtime resolver)
- `railsbackend/bin/beta-up`, `railsbackend/bin/beta-down`
- `foaf-auth/service/docker-compose.prod.yml` — `auth-beta` service
- `growoperative-app` (`develop`): `apiBase.ts` (beta backend key → bpi),
  `databaseBanner.ts` (BETA label)

## DNS (already set, verified 2026-06-24)

`bpi.growoperative.app` A → 35.163.185.37 · `bauth.foaf.io` A → 35.163.185.37

---

## Execution order (prod)

### 1. MySQL — create beta DBs + users

SSH to the box, then to MySQL via the ProxyCommand pattern, log in as root:

```sql
CREATE DATABASE growoperative_beta CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE foaf_auth_beta     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'growoperative_beta'@'%' IDENTIFIED BY '<gen strong pw>';
GRANT ALL PRIVILEGES ON growoperative_beta.* TO 'growoperative_beta'@'%';

CREATE USER 'foaf_auth_beta'@'%' IDENTIFIED BY '<gen strong pw>';
GRANT ALL PRIVILEGES ON foaf_auth_beta.* TO 'foaf_auth_beta'@'%';
FLUSH PRIVILEGES;
```

Record both passwords (1Password: `growoperative_beta_db`, `foaf_auth_beta_db`).

### 2. Write `.env.beta` on the box (NOT committed; chmod 600)

`~/railsbackend/.env.beta` — copy `.env.demo`, change:

```dotenv
DATABASE_NAME=growoperative_beta
DATABASE_USERNAME=growoperative_beta
DATABASE_PASSWORD=<from 1Password>
FRONTEND_URL=https://beta.growoperative.app
SECRET_KEY_BASE=<openssl rand -hex 64>        # fresh, not demo's
DEVISE_JWT_SECRET_KEY=<openssl rand -hex 64>  # fresh
# FOAF auth wiring -> beta auth (container name + public host)
FOAF_AUTH_BASE_URL=http://auth-beta:3000
FOAF_AUTH_PUBLIC_BASE_URL=https://bauth.foaf.io
FOAF_AUTH_ISSUER=bauth.foaf.io
FOAF_AUTH_JWKS_URL=http://auth-beta:3000/.well-known/jwks.json
FOAF_AUTH_REVOCATION_SNAPSHOT_URL=http://auth-beta:3000/v1/revocations/snapshot
FOAF_AUTH_SERVICE_TOKEN=<minted in step 6>
# S3: reuse demo uploads bucket for now (low-stakes test images; split later)
AWS_S3_BUCKET=<demo bucket, or new growoperative-uploads-beta>
```

`~/foaf-auth/service/.env.beta` — copy `.env.demo`, change:

```dotenv
DATABASE_NAME=foaf_auth_beta
DATABASE_USERNAME=foaf_auth_beta
DATABASE_PASSWORD=<from 1Password>
SECRET_KEY_BASE=<openssl rand -hex 64>
REDIS_URL=redis://redis-demo:6379/1            # shared instance, separate logical DB
FOAF_AUTH_ISSUER=bauth.foaf.io
FOAF_AUTH_DEFAULT_AUD=growoperative
FOAF_AUTH_ALLOWED_ORIGINS=https://beta.growoperative.app
FOAF_AUTH_LOCKOUT_HMAC_SECRET=<openssl rand -hex 32>
FOAF_AUTH_RECOVERY_HMAC_SECRET=<openssl rand -hex 32>
FOAF_AUTH_AVATAR_BACKEND=local                 # no S3 bucket needed for beta
DEMO_TOKEN_ISSUER_ENABLED=true                 # beta is a demo-style sandbox
FOAF_AUTH_ACCEPT_DEMO_KIDS=true
```

### 3. Issue TLS certs FIRST (before deploying the new nginx.conf)

The currently-running nginx serves `/.well-known/acme-challenge/` for unknown
hosts via its default (first) :80 server, so webroot works for bpi/bauth even
though no dedicated :80 block exists yet:

```bash
cd ~/railsbackend
sudo docker compose -f docker-compose.prod.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d bpi.growoperative.app -d bauth.foaf.io \
  --email <robin> --agree-tos --no-eff-email
```

Certs MUST exist before the new nginx.conf (with the :443 beta blocks) is
loaded, or nginx fails on a missing cert file.

### 4. Pull the staged code on the box

`git pull` in `~/railsbackend` and `~/foaf-auth`. (Do NOT push foaf-auth to
GitHub until certs exist — its deploy-demo workflow force-recreates nginx using
railsbackend's nginx.conf, which now references the beta certs.)

### 5. Build beta images

```bash
sudo docker compose -f ~/railsbackend/docker-compose.prod.yml --profile beta build backend-beta
sudo docker compose -f ~/foaf-auth/service/docker-compose.prod.yml --profile beta build auth-beta
```

### 6. Bring up auth-beta, mint keys + service token

```bash
sudo docker compose -f ~/foaf-auth/service/docker-compose.prod.yml --profile beta up -d auth-beta
# entrypoint migrates foaf_auth_beta. Then:
sudo docker exec foaf-auth-auth-beta-1 bundle exec rake auth:keys:rotate
sudo docker exec -e AUDIENCE=growoperative -e LABEL=railsbackend-beta \
  foaf-auth-auth-beta-1 bundle exec rake auth:service_tokens:issue   # prints token once
```

> **Do NOT pass `-e DEMO=true` to `auth:keys:rotate`.** It mints a `demo: true`
> signing key (kid `demo-…`), but the login path signs tokens via
> `AuthSigningKey.current!` which defaults to `demo: false` and looks up a `prod-…`
> key only. A demo-only key ⇒ `NoActiveSigningKeyError` ⇒ **every login 500s and the
> app shows "invalid credentials."** `DEMO_TOKEN_ISSUER_ENABLED` / `FOAF_AUTH_ACCEPT_DEMO_KIDS`
> are *verifier*-side flags; the issuer ignores them. Rotate WITHOUT the flag so a
> `prod` key is minted. (Bit us on 2026-07-01 — beta login was dead from first bring-up.)

Put the printed token into `~/railsbackend/.env.beta` → `FOAF_AUTH_SERVICE_TOKEN`.

### 7. Bring up backend-beta + reload nginx

```bash
sudo docker compose -f ~/railsbackend/docker-compose.prod.yml --profile beta up -d backend-beta
# validate nginx against the live network, then reload:
cd ~/railsbackend && sudo docker run --rm --network railsbackend_default \
  -v $PWD/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $PWD/nginx/certbot/conf:/etc/letsencrypt:ro nginx:alpine nginx -t
sudo docker compose -f docker-compose.prod.yml up -d --force-recreate nginx
```

### 8. Seed beta from the trade-test snapshot

Adapt `bin/foaf-reset-demo` → `bin/foaf-reset-beta` (retarget the allowlist to
`growoperative_beta` / `foaf_auth_beta`, containers `railsbackend-backend-beta-1`
/ `foaf-auth-auth-beta-1`; drop the foaf-testnet steps since beta does not publish to FOAF).
It loads the paired `dev_clean_*` → growoperative_beta and `auth_clean_*` →
foaf_auth_beta (foaf_id alignment), and enables the debug API.

### 9. Smoke

```bash
curl -sS -i https://bauth.foaf.io/v1/health           # {"status":"ok"}
curl -sS https://bauth.foaf.io/.well-known/jwks.json | jq '.keys | length'   # 1
curl -sS -i https://bpi.growoperative.app/v1/...        # app responds
```

### 10. Ship the frontend

Commit + push `growoperative-app` `develop` → Cloudflare `growoperative-beta`
rebuilds → `beta.growoperative.app` now talks to `bpi`. Confirm the banner reads
**BETA** and login works against beta auth.

## Day-2

- **Use beta:** `./bin/beta-up` … test … `./bin/beta-down`.
- **Re-seed:** `./bin/foaf-reset-beta` (while up).
- **Rollback:** `./bin/beta-down` removes the containers; nginx falls back to the
  maintenance page for bpi/bauth. The beta DBs persist untouched.
