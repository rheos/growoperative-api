# Plan: eliminate N+1 queries in `ItemsController#index`

Status: planned, not started. Companion to `db_index_audit.md`.

## Why this one

`GET /v1/items` is the item-feed endpoint and the worst N+1 offender in the app.
Unlike the index work, this cost is real **today** — it scales with a user's network
size and inventory count, not total DB size. The method also recurses across network
degrees (`all_items`), so each N+1 is multiplied per hop.

All line numbers are `app/controllers/api/v1/items_controller.rb` unless noted.

## The N+1 inventory (what repeats, per request)

| Location | Repeated query | Multiplier |
|---|---|---|
| `:22`, `:25`, `:108` | `User.find(id)` then `only_consumer_retailer?`/`has_role?` (each reads `user_groups`) | × related users, × 2 queries each |
| `:42`, `:43` | `item.item_requests.count` + `.where(...).first` | × items |
| `:45`, `:55`, `:115`, `:123` | `helpers.get_relation_price` → up to 3 queries (`UserRelationshipPrice` → `UserCategoryPrice` → subnet config), see `item_helper.rb:2` | × items and × users-per-hop |
| `:80`, `:81` | `item.item_requests.where(...)` + `RequestContract...sum(:quantity)` | × items |
| `:100` | `item.to_json(current_user)` (`inventory.rb:65`) loads associations per item | × items |
| `:107`–`:124` | `all_items` recursion repeats relationships + `User.find` + inventory + pricing **at every degree** | × users ^ degree |

Already done well (use as the template): `:88`–`:95` builds `pending_requests` in a
single grouped query. The fix is to make the rest look like that.

## Fix strategy

Phased, lowest-risk first. Each phase is independently shippable and measurable.

### Phase 0 — Safety net (do first)
- Add a characterization test: snapshot the JSON of `items#index` for a known dev
  user across `range_degree` 0–3. The markup-chain math (`apply_markup_chain`) is
  correctness-sensitive; the refactor must preserve output byte-for-byte.
- Add `bullet` gem to the `development`/`test` group to surface N+1s and confirm the
  count drops. Capture a before-count for the test user as the baseline.

### Phase 1 — Batch user + role loading (biggest cheap win)
- Replace every `User.find(id)` inside `.select{}` (`:22,:25,:108`) with a single
  `User.where(id: ids).includes(:user_groups)` loaded once, keyed into a hash.
- Make `only_consumer_retailer?`/`has_role?`/`is_producer?` read the preloaded
  `user_groups` association instead of re-querying (they already operate on
  `user_groups`; preloading is enough — no method change needed if associations are
  eager-loaded).

### Phase 2 — Batch pricing
- `get_relation_price` is called per item and per user-per-hop. Precompute the markups
  needed for the request:
  - Collect all `(seller_id, buyer_id)` pairs up front.
  - Bulk-load `UserRelationshipPrice.where(user_id: sellers, friend_id: buyer)` and
    `UserCategoryPrice.where(user_id: sellers)` into hashes.
  - Add a memoized `relation_price_for(seller, buyer)` that reads those hashes; fall
    back to the existing subnet-config cache (`@subnet_config_cache` already exists in
    `item_helper.rb`).
- Add the deferred `user_relationship_prices(user_id, friend_id)` index once this is
  the access pattern (see audit doc).

### Phase 3 — Batch per-item request data
- Replace `:42,:43,:80,:81` per-item queries with set-based loads keyed by item id:
  - One `item_requests` query for the relevant items/statuses, grouped in Ruby.
  - One `RequestContract.where(id: ...).group(...).sum(:quantity)` instead of one sum
    per item.
- Eager-load associations that `Inventory#to_json` (`inventory.rb:65`) touches so
  `:100` stops lazy-loading per item. Inspect `to_json` first to list them.

### Phase 4 — The recursion (`all_items`), structural
- Lowest priority because Phases 1–2 already remove the per-iteration N+1 inside it.
- If still hot: rewrite the recursive `all_items` as an iterative BFS that collects all
  node ids per degree first, then does one relationships query, one users query, and
  one inventories query **per level** (set-based) instead of per node. This is the
  larger refactor; do it only if profiling after Phases 1–3 still shows it dominating.

## Verification

- Re-run the Phase 0 characterization test after each phase — output must not change.
- Compare `bullet` / query-log counts before vs. after for the test user at
  `range_degree=3`. Target: query count flat (O(1) in network size) for user/role and
  pricing loads, instead of linear/exponential.

## Risk notes

- The markup-chain ordering in `all_items` (`route_markups` accumulation) is subtle —
  preserve the exact composition order when batching pricing.
- The raw interpolated SQL in this method should be parameterized as part of the
  refactor (security + plan caching), but keep that as a clearly separate commit so a
  behavior regression is easy to bisect.
