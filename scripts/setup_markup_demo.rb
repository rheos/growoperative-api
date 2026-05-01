# Establishes the canonical post-reset markup state for the trade test:
#   - apply_first_hop_markup=true on inventories where the holder isn't the
#     original producer (mirrors the legacy producer_owns? semantics).
#   - A handful of UserCategoryPrice + UserRelationshipPrice rows so the
#     percent/flat code paths get exercised by the BFS chain pricing.
#
# Idempotent. Run after bin/foaf-reset, before scripts/trade_test.py.

flagged = 0
Inventory.find_each do |inv|
  is_producer = inv.user_id == inv.item.producer_id
  next if inv.apply_first_hop_markup == !is_producer
  inv.update_column(:apply_first_hop_markup, !is_producer)
  flagged += 1
end
puts "  apply_first_hop_markup synced on #{flagged} inventories"

category = Category.find_by(category_name: 'herbs and greens') || Category.first
abort "  No category found — bail" unless category

ucp_seeds = [
  { user_name: 'bruce',  price: 15,   price_type: 'percent' },
  { user_name: 'barry',  price: 1.50, price_type: 'flat'    },
  { user_name: 'clark',  price: 8,    price_type: 'percent' },
  { user_name: 'oliver', price: 0.75, price_type: 'flat'    },
  { user_name: 'bob',    price: 5,    price_type: 'percent' },
]

ucp_count = 0
ucp_seeds.each do |row|
  user = User.find_by(user_name: row[:user_name])
  next unless user
  ucp = UserCategoryPrice.find_or_initialize_by(user_id: user.id, category_id: category.id)
  ucp.price = row[:price]
  ucp.price_type = row[:price_type]
  ucp_count += 1 if ucp.changed?
  ucp.save!
end
puts "  UserCategoryPrice rows touched: #{ucp_count} (target: #{ucp_seeds.size})"

urp_seeds = [
  { user: 'bob',    friend: 'dianna', price: 5,    price_type: 'percent' },
  { user: 'bruce',  friend: 'barry',  price: 0.50, price_type: 'flat'    },
  { user: 'clark',  friend: 'oliver', price: 12,   price_type: 'percent' },
  { user: 'oliver', friend: 'barry',  price: 1.00, price_type: 'flat'    },
  { user: 'barry',  friend: 'john',   price: 20,   price_type: 'percent' },
]

urp_count = 0
urp_seeds.each do |row|
  user = User.find_by(user_name: row[:user])
  friend = User.find_by(user_name: row[:friend])
  next unless user && friend
  rel = Relationship.where(user_id: [user.id, friend.id], friend_id: [user.id, friend.id]).first
  next unless rel
  urp = UserRelationshipPrice.find_or_initialize_by(
    user_id: user.id, friend_id: friend.id,
    category_id: category.id, relationship_id: rel.id
  )
  urp.price = row[:price]
  urp.price_type = row[:price_type]
  urp_count += 1 if urp.changed?
  urp.save!
end
puts "  UserRelationshipPrice rows touched: #{urp_count} (target: #{urp_seeds.size})"

seed = User.order(:id).first
subnet = seed.primary_subnet
cfg = SiteConfig.for(subnet)
puts ""
puts "  Subnet: #{subnet&.name || '(none)'}"
puts "  default_markup: #{cfg[:default_markup]}, default_markup_type: #{cfg[:default_markup_type]}"
puts "  chain_limit: #{cfg[:chain_limit]}"
