# Contabo/Neon tier migration runbook

Move a GrowOperative tier (railsbackend + foaf-auth + foaf-protocol) off Lightsail/MySQL onto **Contabo/Coolify + Neon Postgres**. Order: **beta → demo → prod** (prod last + explicit). Proven on **beta 2026-08-16**; this runbook is the distilled gotchas so demo/prod go smoother.

Cross-repo: touches `railsbackend`, `foaf-auth`, `foaf-protocol-ruby`, and (config only) `growoperative-app` + `foaf-client`. **Run the migration from `~/Code/foaftech`** (the common root). From there the sub-project `CLAUDE.md`s do NOT auto-load — read them + this runbook at kickoff.

## Golden rule: preserve hostnames → no app-store release
Keep the **public hostnames stable** (`api`/`dpi.growoperative.app`, `auth`/`dauth.foaf.io`) and keep the API **transparent** (custody routing + the Neon move are invisible to clients). Cut over by **DNS**, not by shipping a client. Native apps have the hostnames baked in at build time, so a DNS flip needs **no native release**. The only things that would force an app update: changing a baked-in hostname, or a breaking API change — do neither as part of this migration.

## Blue-green cutover (the demo-temp approach)
1. Stand up the new stack on Contabo/Neon with the **final** values for the switch-invariant bits, so tokens minted during verification survive the flip: JWT issuer (`FOAF_AUTH_ISSUER` = the final auth host), audience (`FOAF_AUD=growoperative`), `FOAF_AUTH_JWKS_URL`, `AWS_S3_BUCKET`, `COOKIE_DOMAIN=.growoperative.app`.
2. Expose it for verification via a **temp DNS** (`demo-temp.growoperative.app`). Make **only** the CORS origins + the frontend's API target temp-aware, and **additive** (accept both `demo-temp` and the final `demo` origin).
3. Lower DNS TTL on the real hostnames **before** the flip.
4. Verify end-to-end on the temp host (see Verification gate). Then repoint the real hostnames' DNS to Contabo. Drop the temp origins afterward.
5. Hostname-coupled things to watch on temp: CORS allowlists (backend for login, auth's own list), **OAuth redirect URIs** (registered per-domain — temp needs its own or skip OAuth in the temp verify). Cookie domain + issuer + audience stay constant if you use final values from step 1.

## Per-tier config that MUST be set (each item bit us on beta)
**foaf-auth:**
- Signing keys rotated: `rails auth:keys:rotate` (prod key, demo=false) **and** `rails auth:demo:rotate_key` (demo key, demo=true). A fresh tier has **0** keys → login + demo-token issuance 500. Demo tokens need the demo key specifically.
- `DEMO_TOKEN_ISSUER_ENABLED=true` (the `/v1/internal/demo_tokens` route only registers when true).
- Identities loaded, `foaf_id`-aligned to backend `users` (token resolution does `User.find_by(foaf_id:)`).
- `config/demo_foaf_ids.yml` allowlist covers the demo foaf_ids (source-controlled, baked in the image).
- Audience: `REGISTERED_AUDIENCES = [growoperative, orchardly, onloan]` (base_controller.rb). The tier client_id MUST be one of these. `FOAF_AUTH_DEFAULT_AUD` is only a no-client_id fallback — don't rely on it.

**backend (railsbackend):**
- **`FOAF_AUD=growoperative`** — the REGISTERED value, NOT a tier nickname like `growop`. (Beta had `growop` → login proxy sent an unregistered client_id → auth 400 → generic 401.)
- **`AWS_S3_BUCKET`** = the tier bucket (`growoperative-uploads-demo`). Unset → carrierwave.rb falls back to `growoperative-uploads-production` → item images 403. (The `avatars` field on Item/Inventory IS the item images.)
- `global_settings.debug_api_enabled = 1` (fresh Neon has none → `/v1/debug/*` 403; the trade test needs it).
- Demo users marked: `user_groups.group_label = 'demo'` (enum value **6**). The `dev_clean` snapshot already carries these for the 13 `CORE_DEMO_USERNAMES` (robin is NOT a demo user).
- **Raw-SQL Postgres port COMPLETE** — not just the `neon-fixes.patch` subset. See "The audit still owed."
- `FOAF_AUTH_SERVICE_TOKEN` reconciled with auth (SHA256 hash in auth's `service_tokens`, audience-scoped) — else internal calls (revocation snapshot) 401.

## Symptom → cause (fastest triage)
| Symptom | Cause | Fix |
|---|---|---|
| Login "invalid handle or password" | backend `FOAF_AUD` = unregistered nickname → auth 400 → generic 401. (Also fires on backend/DB unreachable — ambiguous error.) | `FOAF_AUD=growoperative` |
| Login 500 / demo-login "Demo token issuance failed" | foaf-auth has 0 signing keys | `auth:keys:rotate` + `auth:demo:rotate_key` |
| demo-login route 404 | `DEMO_TOKEN_ISSUER_ENABLED` unset | set true + redeploy |
| `/v1/debug/invariants` 403 "Debug API is disabled" | no `global_settings.debug_api_enabled=1` | insert it |
| "Failed to load available items" / `/v1/items?range_degree≥1` 500 | unported raw SQL: `PG::DatatypeMismatch: argument of AND must be type boolean, not type bigint` (COUNT-as-boolean) | `> 0`; real fix = full audit |
| Item images 403 / not showing | no `AWS_S3_BUCKET` → wrong bucket | `AWS_S3_BUCKET=growoperative-uploads-demo` |
| backend log `[foaf-auth-verifier] snapshot fetch failed: HTTP 401` | service-token handshake mismatch | reconcile `FOAF_AUTH_SERVICE_TOKEN` (fail-open now; fix before prod) |

## Data load (proven byte-faithful on beta)
- **Password digests migrate byte-identical** (md5 MySQL == Neon). Do NOT hand-set passwords — the migration carries them; prod can't be reset. A wrong password guess is not a migration fault. Demo users = `bobsentme!`.
- Mechanics: MySQL relay → pgloader → local PG stage → pg_dump → Neon, as one atomic **drop-FK / truncate / load / re-add-FK** txn (Neon blocks `session_replication_role`, so drop/re-add all FKs). Exclude drift tables (`global_settings`, `schema_migrations`, `ar_internal_metadata`). Casts: `tinyint(1)→bool`, `datetime→timestamptz`, zero-dates→null. Neon SNI: libpq needs `?options=endpoint%3D<id>`; pgloader can't SNI → hence the stage relay.
- **Ledger (foaf-protocol) is the unrehearsed, load-bearing one** — beta stood it up fresh. Real balances port with **SHA-256 balance-hash parity** as the acceptance gate (the July protocol-migration precedent).

## Custody / one-address migration is BUNDLED with this move
The deployed branches carry both: railsbackend `agent/beta-neon-custody-combined` = "Neon adapter + SQL fixes **on the custody base**"; foaf-auth beta builds from `bureau/20260814-one-address-build` (identity gains `foaf_address` varchar(42) **unique** + `foaf_encrypted_private_key` + `custodian_key_events`). So rolling this migration rolls out the **one-address custodian** too — the address + key move OUT of railsbackend ONTO the shared foaf-auth identity, so any app reads the ledger address from the session. Neither is on main yet; both merge + deploy together per tier. (It's API-transparent — clients see no change — so bundling the DB move with the identity-model change is acceptable; decoupling would mean un-bundling the branch.)

**Standup step (run AFTER the data load, each tier):** `bundle exec rake foaf_custody:migrate_keys` on the backend (needs `FOAF_AUTH_URL` + `FOAF_AUTH_SERVICE_TOKEN_GROWOP`). Idempotent; `DRY_RUN=true` first. It derives-verifies each key→address, hands the key to the custodian, probe-signs to verify, then nulls the local key + sets `custody_state=migrated`. Verify: `identities.foaf_address`/`foaf_encrypted_private_key` populated, address parity (auth == railsbackend) exact, railsbackend `foaf_private_key` nulled. **rack-attack 429** throttles the custodian endpoint under a burst → just re-run (idempotent, retries "error"/pending users; "migrated" stay excluded). Users with no local key (never registered) stay `pending` — expected.

**ENTANGLEMENT TRAP (bit beta 2026-08-16):** the custodied address + key live ON the identity rows. **Reloading auth identities from a pre-custody dump (e.g. a `dev_clean`/`auth_clean` snapshot) TRUNCATEs them away** — `foaf_address` + `foaf_encrypted_private_key` go NULL, custody is undone, addresses fall back into railsbackend. Only `custodian_key_events` (separate table) survives, orphaned. So: run the custody migration **after** the data load, and never reload the identities table afterward without re-running it. On beta the reseed silently reverted custody to pre-custody state; caught only on inspection.

## Login architecture (test the right thing)
Browser → **backend** `/v1/sessions` → `AuthFoafClient.login` → auth internal `/v1/sessions`. (Job 35 will later repoint browser→auth directly.) So: CORS for login is on the **backend**; field names differ across the hop — web app sends **`username`**, backend reads `params[:username]` → auth wants **`user_name`**.

## Coolify / infra
API only from the box: `ssh root@144.126.145.4` → `http://localhost:8000/api/v1` (port 8000 not open to Robin's IP). v4.3.2: **deploy is POST** `…/deploy?uuid=`; env create=POST, update=PATCH; **env change needs a redeploy**. App→app needs `custom_network_aliases`; app→DB auto. Source = Coolify **GitHub App** "foaf-foundation" (org disables deploy keys). Deployment status reads `running:unknown` (runtime, not progress) — poll the real outcome (login/browse=200), not the status.

## Verification gate (don't declare done early)
Health checks + an **empty** invariants response prove nothing — they don't touch the raw SQL or auth. Before calling a tier done: real **login** (browser field `username`) → **browse** `/v1/items` at every `range_degree` → **item images** resolve (200) → a **trade test** flow. On beta, "trade-test-ready" was claimed on login + empty-invariants and was wrong; the first real browse 500'd.

## The audit still owed (Phase-3, ~week of 2026-08-17)
The railsbackend raw-SQL → Postgres port is INCOMPLETE. `neon-fixes.patch` got it to boot + log in but missed query paths (confirmed: `items_controller` COUNT-as-boolean, fixed stopgap in `2db56c0`). **Run the railsbackend RSpec suite against local Postgres 16** — strict-type errors light up every remaining breaker (`bool = 0/1`, `IN(...) > 0`, COUNT-as-boolean, interpolated `.where`). Fix them all before demo/prod. This is the bigger half of the "dataport" work: porting the QUERIES, not just the rows.
