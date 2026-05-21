# DB index audit — 2026-05-21

Read-only audit of the SELECTs the app makes vs. the schema's indexes, prompted by
the MySQL OOM incident. Indexes below were added in
`db/migrate/20260521120000_add_performance_indexes.rb`.

## Context / honest scaling note

Prod DB is ~1.7 MB / ~13-user demo network. At this size MySQL often skips indexes
and scans anyway, so these add little measurable speed **today**. They are cheap
insurance that engages as tables grow, and they keep table scans from becoming the
next CPU/IO pathology. The N+1 work (see `n_plus_one_items_index.md`) is what helps
*now*.

`jwt_blacklist.jti` (hit on every authenticated request) is already indexed — the
700s query times during the incident were OOM/swap thrash, not a missing index.

## Indexes added

| Index | Evidence | Class |
|---|---|---|
| `relationships(friend_id)` | `Relationship.where("user_id=X OR friend_id=X")` everywhere (items/item_requests/users/subnets/inventory). Only `user_id` was indexed. | scale |
| `orders(user_id, friend_id, order_status)` + `orders(friend_id)` | `Order.find_or_create_pending` (`order.rb:19`) on every accept/ship/reserve; `orders_controller:36`. Both cols were unindexed. | scale |
| `request_contracts(inventory_id)` | Correlated `COUNT` subquery per inventory row, `item_requests_controller:462`, `items_controller:30`. | now + scale |
| `item_requests(friend_id)`, `item_requests(order_id)` | Seller-side dashboard + order grouping. | scale |
| `invitations(invitation_code)` | `find_by(invitation_code:)` on signup/accept + `exists?` per code gen (`invitation.rb:29,47`). | scale |
| `inventories(user_id, status)`, `inventories(ref_id)` | Item listing status filters; `ref_id` links reserved copies. | scale |
| `unit_options(inventory_id)`, `category_sizes(user_id, category_id)` | Tables had zero non-PK indexes. | minor |

## Not done (deliberately)

- `user_relationship_prices(user_id, friend_id)` — `get_relation_price` does
  `find_by(user_id:, friend_id:)` but `friend_id` is unindexed. Low-traffic once the
  N+1 batching lands; revisit then.
- Normalizing `orders.user_id`/`friend_id` from `varchar` to integer FKs — latent
  query-plan foot-gun, but a data migration; defer.
- Parameterizing the raw interpolated SQL (`"user_id = #{...}"`) — security item,
  tracked separately, also enables plan caching.

## Status

Migration applied to local dev DB; `schema.rb` regenerated. Not yet deployed —
ships to demo on next push to master, prod on manual promote (index creation is
instant at this data size).
