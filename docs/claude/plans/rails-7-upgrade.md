# Rails 7.1 / Ruby 3.2 upgrade — railsbackend + foaf-auth

**Status:** Implemented locally (2026-07-24). Both `railsbackend` and `foaf-auth/service` are on Rails 7.1.6 / Ruby 3.2.11 with green Dockerized suites.
**Verification:** `foaf-auth/service`: `zeitwerk:check` green, `320 examples, 0 failures`. `railsbackend`: `zeitwerk:check` green, `528 examples, 0 failures, 15 pending`, `assets:precompile` green.
**Goal:** Bring the two legacy services off double-EOL (Rails 5.2 EOL 2022, Ruby 2.6/2.7 EOL) up to **Rails 7.1 / Ruby 3.2**, matching orchardly-rails, onloan-api, and foaf-protocol-ruby.
**Scope:** `Growoperative/railsbackend` and `foaf-auth/service`. They share the stack and a JWT/RS256 auth contract, so they upgrade on one shared playbook.

## Current state
| App | Rails | Ruby | Test suite | Shape |
|---|---|---|---|---|
| railsbackend | 5.2.8.1 | 2.6.3 (`.ruby-version`; lockfile says 2.7.8 — reconcile) | RSpec, ~79 specs (32 model / 25 controller / 6 request / 14 service) | full-stack (NOT api_only, despite CLAUDE.md) |
| foaf-auth/service | 5.2.8.1 | 2.7.8 | RSpec, 48 files / ~319 examples (heavy request specs on the auth contract) | api-only, clean |

## Headline
This is a **disciplined multi-step walk, not a rewrite. Both apps are MEDIUM effort** (foaf-auth LOW–MEDIUM). The scary-looking items deflated on inspection:
- **`spawnling` is a non-issue** — only reference is a commented-out line; delete from Gemfile, zero code change. (Not a job-backend migration.)
- **railsbackend's giant asset-pipeline gem list is deletable, not upgradable** — turbolinks/jquery/jquery-ui/coffee-rails/coffee-script/sassc-rails/uglifier/react-rails/font-awesome-rails are vestigial (frontends live on Cloudflare Pages; the dashboard view is dead). Deleting them shrinks the surface.
- **JWT is already modern on both sides** — foaf-auth on `jwt` 3.1.2, railsbackend on 2.10.1, both using version-stable decode/verify APIs. The crypto-migration risk is largely pre-absorbed.
- **Both codebases are unusually clean** — no `update_attributes`, correct `belongs_to optional:`, `ApplicationRecord`, already-safe YAML (foaf-auth). They've been tidied once already.

## The real work (concentrated in a few places)
1. **Ruby bump.** railsbackend 2.6→2.7→3.2; foaf-auth 2.7→3.2. Rebuild native exts (mysql2, nokogiri, bcrypt, argon2/ffi, rmagick). Ruby 3.x forces the Rails-7 finish line.
2. **Zeitwerk (Rails 6.0).** The highest-surface change.
   - **foaf-auth: the most likely boot failure.** `config.autoload_paths << lib` (`config/application.rb:23`) with non-Ruby files under `lib/` (`lib/tasks/*.rake`, `lib/bip39/*.txt`, `*.md`). Fix: `Rails.autoloaders.main.ignore(...)` those, or only autoload `lib/middleware`; drop the redundant `require_relative` of the two middleware files.
   - **railsbackend: currently defused.** `lib/` is NOT on the autoload path (explicit requires via `config/initializers/libs_require.rb`); constant names deliberately don't match Zeitwerk (`lib/jwt/decoding_service.rb` → `JwtDecodingService`). Risk = someone naively adds `lib` to autoload_paths during the upgrade. Also `lib/jwt/` collides with the `jwt` gem namespace. Keep explicit requires or rename files→constants; do not add `lib` to autoload paths. Run `bin/rails zeitwerk:check` after.
3. **`config.load_defaults` walk 5.2→6.0→6.1→7.0→7.1**, flag-by-flag via `new_framework_defaults_*.rb`. railsbackend is full-stack with a manually-mounted cookie/session/flash middleware stack (`application.rb:18-21`), so the 7.0 cookie-serializer / CSRF-format / SameSite defaults need explicit verification there.
4. **rspec-rails bump.** railsbackend 4.1 and foaf-auth 5.x both cap below Rails 7.1 → bump to `~> 6.1` at the 7.0 step (mandatory; the suites can't run on 7 otherwise).
5. **Gem swaps/bumps.** railsbackend: `fast_jsonapi` → `jsonapi-serializer` (drop-in), `nokogiri` ≥1.15 (CVEs), `puma`→6, `rack-cors`→2, `mysql2`≥0.5.6, `rmagick` native rebuild, drop `webdrivers` (Selenium Manager), `selenium-webdriver`≥4.11. foaf-auth: pin `jwt ~> 3.1`, `mysql2`≥0.5.6, widen `ffi` `<1.17` ceiling, `rspec-rails`→6.1.
6. **Small code fixes.**
   - railsbackend: one `serialize :gallery_map, Array` (`app/models/inventory.rb:9`) → 7.1 `type:`/`coder:` signature + verify existing YAML DB values load under safe-load (psych 4).
   - foaf-auth: `Rails.application.secrets.secret_key_base` → `Rails.application.secret_key_base` (`login_lockout_policy.rb:52`, `recovery_lockout_policy.rb:58`; deprecated 7.1, removed 7.2). Re-verify the AR log-bind monkeypatch (`config/initializers/filter_active_record_binds.rb`) against 7.1's native bind filtering.
7. **Crypto / FOAF signing path — test hard.** railsbackend `app/services/foaf/*` + `lib/jwt/*` + the `Thread.new` verifier-refresh loop (`z_foaf_auth_verifier_refresh.rb`) do raw `net/http` + OpenSSL RS256. OpenSSL 3 (Ruby 3.x) is the thing to smoke-test. foaf-auth's `AuthSigningKey` keyring / hand-rolled JWKS is the mirror side.

## Safety nets & verification gates
- Both apps have **genuine RSpec suites covering the risky logic** (JWT/auth contract, settlement/trustlines, revocations, demo-login). That is what makes this safe.
- **No CI test job today** (workflows are deploy-only). **Wire a throwaway CI job that runs `rspec` at every `load_defaults` step** so each phase is gated, instead of relying on manual runs + prod soak.
- **Cross-service JWT round-trip is the cutover gate.** The two services deploy on different days; a token minted by upgraded foaf-auth must still verify in railsbackend and vice-versa. Add a bidirectional round-trip smoke test and run it before each deploy.

## Phased execution plan
Run each phase to a **green suite** before the next. Do **foaf-auth first as the pilot** (smaller, cleaner, already Ruby 2.7 + JWT 3.x) to prove the shared playbook, then apply it to railsbackend.

- **Phase 0 — Prep (both, current stack).** Green the suites as a baseline. Wire the throwaway rspec CI job. Add the cross-service JWT round-trip smoke test. railsbackend: delete the vestigial asset-pipeline gems + `spawnling` + `webdrivers`; swap `fast_jsonapi`→`jsonapi-serializer`. All safe on 5.2.
- **Phase 1 — Ruby 2.6→2.7 (railsbackend only).** Reconcile `.ruby-version` vs lockfile. Rebuild native exts. Green.
- **Phase 2 — Rails 5.2→6.0 (both).** The Zeitwerk phase (see §2). `load_defaults 6.0`. `zeitwerk:check` green + suite green.
- **Phase 3 — Rails 6.0→6.1 (both).** `load_defaults 6.1`, gem bumps. Green.
- **Phase 4 — Rails 6.1→7.0 (both).** `load_defaults 7.0` (cookie/CSRF/cache-format — verify railsbackend's manual middleware). Bump `rspec-rails`→6.1. railsbackend `serialize` fix. Green.
- **Phase 5 — Ruby 2.7→3.2 (both).** Now safe on Rails 7.0. Rebuild all native exts; OpenSSL 3 — hammer the FOAF RS256 signing/verify path. Green + cross-service round-trip.
- **Phase 6 — Rails 7.0→7.1 (both).** `load_defaults 7.1`. foaf-auth `secrets`→`secret_key_base` + bind-filter re-verify + pin `jwt`. Final gem bumps. Green + round-trip.
- **Phase 7 — Cutover & cleanup.** Deploy foaf-auth first, soak, then railsbackend, round-trip gate at each. Fix the railsbackend CLAUDE.md "API mode" line. Update stack docs.

## Out of scope (separate follow-ups)
- **Sidekiq 6→7** (foaf-auth) — 6.5 is EOL but runs on 7.1; bumping to 7 drags redis 4→5. Decide separately, after the Rails upgrade.
- **secrets.yml → credentials** migration — optional; `secret_key_base` accessor swap is enough for 7.1.
- **AMS vs jsonapi-serializer consolidation** (railsbackend carries both) — cleanup, not blocking.

## Sequencing rationale
foaf-auth is the pilot because it's smaller, API-only, already on Ruby 2.7 and JWT 3.x, and its auth layer is the reference implementation for the modern JWT/JWKS patterns. The JWT contract is version-stable and the JWKS output is hand-rolled, so foaf-auth can upgrade first without breaking railsbackend's verification. railsbackend then follows on the proven playbook.
