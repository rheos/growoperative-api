# Adds indexes identified in the 2026-05-21 query/index audit.
# All are additive and non-destructive. Each is guarded so the migration is
# safe to run against demo/prod even if an index already exists (drift-proof).
#
# Rationale per index lives in docs/plans/db_index_audit.md.
class AddPerformanceIndexes < ActiveRecord::Migration[5.2]
  def change
    # #1 Relationship.where("user_id = X OR friend_id = X") is the single most
    # common pattern in the app; only user_id was indexed. Lets MySQL index-merge.
    add_index_safely :relationships, :friend_id

    # #2 Order.find_or_create_pending filters user_id+friend_id+order_status on
    # every accept/ship/reserve. Neither column was indexed.
    add_index_safely :orders, [:user_id, :friend_id, :order_status],
                     name: "index_orders_on_user_friend_status"
    add_index_safely :orders, :friend_id # friend_id-only lookups (snapshot/reset/debug)

    # #3 Correlated subquery in item_requests#index counts request_contracts by
    # inventory_id once per inventory row — bites even at small scale.
    add_index_safely :request_contracts, :inventory_id

    # #4 Seller side of the dashboard + order grouping.
    add_index_safely :item_requests, :friend_id
    add_index_safely :item_requests, :order_id

    # #5 find_by(invitation_code:) on signup/accept + exists? on every code gen.
    add_index_safely :invitations, :invitation_code

    # #6 Item listing filters user_id+status+quantity; ref_id links reserved copies.
    add_index_safely :inventories, [:user_id, :status],
                     name: "index_inventories_on_user_id_and_status"
    add_index_safely :inventories, :ref_id

    # #7 Tables with zero non-PK indexes, queried by these keys.
    add_index_safely :unit_options, :inventory_id
    add_index_safely :category_sizes, [:user_id, :category_id],
                     name: "index_category_sizes_on_user_and_category"
  end

  private

  def add_index_safely(table, columns, **opts)
    name = opts[:name] || "index_#{table}_on_#{Array(columns).join('_and_')}"
    return if index_exists?(table, columns, name: name)
    add_index table, columns, **opts.merge(name: name)
  end
end
