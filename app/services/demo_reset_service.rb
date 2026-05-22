class DemoResetService
  def initialize(snapshot_name: 'default')
    @snapshot_name = snapshot_name
  end

  def call
    @snapshot = DemoSnapshotService.load(@snapshot_name)
    @core_usernames = @snapshot['core_usernames']

    ActiveRecord::Base.transaction do
      delete_spawned_users
      delete_core_demo_data
      # NOTE: foaf_id rotation (old Job 14 token-invalidation step) is
      # deliberately gone. auth.foaf.io is now authoritative for demo login
      # and validates the requested foaf_id against a static allowlist
      # (config/demo_foaf_ids.yml) + an Identity row. Rotating to random
      # UUIDs made every reset fail that check ("foaf_id not in demo
      # allowlist" → 502 on /v1/demo/login). Core demo foaf_ids must stay
      # pinned to the allowlist. Pre-reset session invalidation, if needed,
      # belongs auth-side (tokens_invalid_before); demo tokens are short-
      # lived (≈1h) so stale sessions simply see refreshed data meanwhile.
      restore_core_demo_data
    end
  end

  private

  # --- Tier 1: Delete users created by visitors via demo invitations ---

  def delete_spawned_users
    spawned = User.demo.where.not(user_name: @core_usernames)
    return if spawned.empty?

    spawned_ids = spawned.pluck(:id)
    Rails.logger.info("[DemoReset] Deleting #{spawned_ids.size} spawned demo users")

    delete_user_data(spawned_ids)

    # Delete the user rows themselves (and their user_groups via dependent: :destroy)
    spawned.destroy_all
  end

  # --- Tier 2: Delete core demo users' transactional data ---

  def delete_core_demo_data
    core_ids = User.where(user_name: @core_usernames).pluck(:id)
    Rails.logger.info("[DemoReset] Clearing transactional data for #{core_ids.size} core demo users")

    delete_user_data(core_ids)
  end

  # Shared delete logic for both spawned and core users
  def delete_user_data(user_ids)
    return if user_ids.empty?

    # Relationships between these users
    rel_ids = Relationship.where(user_id: user_ids).or(Relationship.where(friend_id: user_ids)).pluck(:id)

    # Delete in reverse dependency order
    RequestListRelationshipStatus.where(relationship_id: rel_ids).delete_all if rel_ids.any?
    UserRelationshipRequestPrice.where(user_id: user_ids).delete_all
    UserRelationshipPrice.where(user_id: user_ids).delete_all
    # Also clear price rows that reference a deleted relationship but are owned
    # by the counterparty (whose user_id isn't in user_ids) — otherwise the
    # relationship delete below trips the relationship_id foreign key.
    if rel_ids.any?
      UserRelationshipRequestPrice.where(relationship_id: rel_ids).delete_all
      UserRelationshipPrice.where(relationship_id: rel_ids).delete_all
    end
    UserCategoryPrice.where(user_id: user_ids).delete_all

    # Trustlines
    trustline_ids = Trustline.where(user_a_id: user_ids).or(Trustline.where(user_b_id: user_ids)).pluck(:id)
    if trustline_ids.any?
      TrustlineTransaction.where(trustline_id: trustline_ids).delete_all
      # PendingPayment references trustlines; clear before deleting the parent.
      PendingPayment.where(trustline_id: trustline_ids).delete_all
      Trustline.where(id: trustline_ids).delete_all
    end

    # Inventories and their dependents
    inventory_ids = Inventory.where(user_id: user_ids).pluck(:id)
    UnitOption.where(inventory_id: inventory_ids).delete_all if inventory_ids.any?

    # Items and their dependents
    item_ids = Item.where(user_id: user_ids).pluck(:id)
    ItemRelationship.where(item_id: item_ids).delete_all if item_ids.any?
    ItemRelationship.where(relationship_id: rel_ids).delete_all if rel_ids.any?
    Review.where(user_id: user_ids).delete_all

    # Requests and orders
    ItemRequest.where(user_id: user_ids).or(ItemRequest.where(friend_id: user_ids)).delete_all
    RequestContract.where(user_id: user_ids).delete_all
    Order.where(user_id: user_ids).or(Order.where(friend_id: user_ids)).delete_all

    # Inventories and items
    Inventory.where(id: inventory_ids).delete_all if inventory_ids.any?
    Item.where(id: item_ids).delete_all if item_ids.any?

    # Relationships and category sizes
    Relationship.where(id: rel_ids).delete_all if rel_ids.any?
    CategorySize.where(user_id: user_ids).delete_all
  end

  # --- Restore core demo data from snapshot ---

  def restore_core_demo_data
    # Build name → id map for core demo users
    @name_to_id = User.where(user_name: @core_usernames).pluck(:user_name, :id).to_h

    Rails.logger.info("[DemoReset] Restoring data from snapshot (captured #{@snapshot['captured_at']})")

    restore_user_attributes
    restore_user_groups
    restore_relationships
    restore_trustlines
    restore_items_and_inventories
    restore_orders_and_requests
    restore_pricing
    restore_category_sizes
    restore_reviews
  end

  def restore_user_attributes
    (@snapshot['users'] || []).each do |u|
      user = User.find_by(user_name: u['user_name'])
      next unless user
      user.update_columns(
        name: u['name'],
        nickname: u['nickname'],
        depth: u['depth'],
        invite_limit: u['invite_limit'],
        invitation_limit: u['invitation_limit'],
        invitations_count: u['invitations_count'],
        parent_id: u['parent_user_name'] ? @name_to_id[u['parent_user_name']] : nil,
      )
    end
  end

  def restore_user_groups
    core_ids = @name_to_id.values
    # Clear existing and re-create from snapshot
    UserGroup.where(user_id: core_ids).delete_all
    (@snapshot['user_groups'] || []).each do |ug|
      uid = @name_to_id[ug['user_name']]
      next unless uid
      UserGroup.create!(user_id: uid, group_label: ug['group_label'])
    end
  end

  def restore_relationships
    @relationship_map = {} # track for pricing restoration
    (@snapshot['relationships'] || []).each do |r|
      uid = @name_to_id[r['user_name']]
      fid = @name_to_id[r['friend_user_name']]
      aid = @name_to_id[r['action_user_name']]
      next unless uid && fid
      rel = Relationship.create!(
        user_id: uid, friend_id: fid, status: r['status'],
        action_user_id: aid, user_label: r['user_label'], friend_label: r['friend_label'],
      )
      @relationship_map["#{r['user_name']}-#{r['friend_user_name']}"] = rel.id
    end
  end

  def restore_trustlines
    @trustline_map = {}
    (@snapshot['trustlines'] || []).each do |t|
      a_id = @name_to_id[t['user_a_name']]
      b_id = @name_to_id[t['user_b_name']]
      next unless a_id && b_id
      tl = Trustline.create!(
        user_a_id: [a_id, b_id].min, user_b_id: [a_id, b_id].max,
        credit_limit_a_to_b: t['credit_limit_a_to_b'],
        credit_limit_b_to_a: t['credit_limit_b_to_a'],
        current_balance: t['current_balance'],
        is_active: t['is_active'],
        notes: t['notes'],
      )
      @trustline_map["#{t['user_a_name']}-#{t['user_b_name']}"] = tl.id
    end

    # Restore trustline transactions
    (@snapshot['trustline_transactions'] || []).each do |tt|
      tl_id = @trustline_map["#{tt['trustline_user_a_name']}-#{tt['trustline_user_b_name']}"]
      next unless tl_id
      TrustlineTransaction.create!(
        trustline_id: tl_id,
        amount: tt['amount'],
        description: tt['description'],
        transaction_type: tt['transaction_type'],
        initiated_by_id: @name_to_id[tt['initiated_by_name']],
        balance_after: tt['balance_after'],
        is_reversed: tt['is_reversed'],
        path_info: tt['path_info'],
        created_at: tt['created_at'],
      )
    end
  end

  def restore_items_and_inventories
    @item_ids = [] # ordered list to resolve index references
    @inventory_ids = []

    (@snapshot['items'] || []).each do |i|
      uid = @name_to_id[i['user_name']]
      next unless uid
      item = Item.new(
        user_id: uid,
        category_id: Category.find_by(category_name: i['category_name'])&.id,
        item_name_id: ItemName.find_by(name: i['item_name_value'])&.id,
        grade_id: Grade.find_by(name: i['grade_name'])&.id,
        item_unit_id: ItemUnit.find_by(unit_name: i['unit_name'])&.id,
        quantity: i['quantity'],
        price: i['price'],
        date_available: i['date_available'],
        organic: i['organic'],
        name: i['name'],
        producer_id: @name_to_id[i['producer_user_name']],
      )
      # Skip after_create :add_inventory — snapshot includes its own inventories
      item.with_inventory = true
      # Force original ID so CarrierWave S3 paths match existing files
      item.id = i['original_id'] if i['original_id']
      item.save!
      # Write avatars via SQL — update_columns double-escapes the JSON for CarrierWave
      if i['avatars_raw'].present?
        escaped = ActiveRecord::Base.connection.quote(i['avatars_raw'])
        ActiveRecord::Base.connection.execute("UPDATE items SET avatars = #{escaped} WHERE id = #{item.id}")
      end
      @item_ids << item.id
    end

    (@snapshot['inventories'] || []).each do |inv|
      uid = @name_to_id[inv['user_name']]
      item_id = inv['item_index'] ? @item_ids[inv['item_index']] : nil
      next unless uid
      inventory = Inventory.create!(
        user_id: uid, item_id: item_id,
        quantity: inv['quantity'], price: inv['price'],
        status: inv['status'],
        description: inv['description'],
        apply_first_hop_markup: inv['apply_first_hop_markup'] || false,
        ref_price: inv['ref_price'],
      )
      if inv['avatars_raw'].present?
        escaped = ActiveRecord::Base.connection.quote(inv['avatars_raw'])
        ActiveRecord::Base.connection.execute("UPDATE inventories SET avatars = #{escaped} WHERE id = #{inventory.id}")
      end
      @inventory_ids << inventory.id
    end

    (@snapshot['unit_options'] || []).each do |uo|
      inv_id = uo['inventory_index'] ? @inventory_ids[uo['inventory_index']] : nil
      next unless inv_id
      UnitOption.create!(
        inventory_id: inv_id,
        item_unit_id: ItemUnit.find_by(unit_name: uo['unit_name'])&.id,
        price: uo['price'], quantity: uo['quantity'],
      )
    end
  end

  def restore_orders_and_requests
    (@snapshot['orders'] || []).each do |o|
      Order.create!(
        user_id: @name_to_id[o['user_name']],
        friend_id: @name_to_id[o['friend_user_name']],
        order_label: o['order_label'],
        order_status: o['order_status'],
      )
    end

    @request_contract_ids = []
    (@snapshot['request_contracts'] || []).each do |rc|
      uid = @name_to_id[rc['user_name']]
      item_id = rc['item_index'] ? @item_ids[rc['item_index']] : nil
      inv_id = rc['inventory_index'] ? @inventory_ids[rc['inventory_index']] : nil
      next unless uid
      contract = RequestContract.create!(
        user_id: uid, item_id: item_id, inventory_id: inv_id,
        quantity: rc['quantity'], status: rc['status'],
        steps: rc['steps'], current_step: rc['current_step'], unit: rc['unit'],
      )
      @request_contract_ids << contract.id
    end

    # Assign requests to contracts by walking through each contract's step count
    contracts = @snapshot['request_contracts'] || []
    all_requests = @snapshot['item_requests'] || []
    req_index = 0
    contracts.each_with_index do |rc, ci|
      steps = rc['steps'].to_i
      steps.times do
        ir = all_requests[req_index]
        break unless ir
        req = ItemRequest.new(
          user_id: @name_to_id[ir['user_name']],
          friend_id: @name_to_id[ir['friend_user_name']],
          request_contract_id: @request_contract_ids[ci],
          price: ir['price'], status: ir['status'],
          step: ir['step'], sent: ir['sent'],
          accepted_at: ir['accepted_at'],
          shipped_at: ir['shipped_at'],
          signed_at: ir['signed_at'],
        )
        req.save!
        req_index += 1
      end
    end
  end

  def restore_pricing
    (@snapshot['user_category_prices'] || []).each do |ucp|
      UserCategoryPrice.create!(
        user_id: @name_to_id[ucp['user_name']],
        category_id: Category.find_by(category_name: ucp['category_name'])&.id,
        price: ucp['price'],
        price_type: ucp['price_type'] || 'flat',
      )
    end

    (@snapshot['user_relationship_prices'] || []).each do |urp|
      uid = @name_to_id[urp['user_name']]
      fid = @name_to_id[urp['friend_user_name']]
      rel_id = @relationship_map["#{urp['user_name']}-#{urp['friend_user_name']}"]
      next unless uid && fid
      UserRelationshipPrice.create!(
        user_id: uid, friend_id: fid,
        category_id: Category.find_by(category_name: urp['category_name'])&.id,
        relationship_id: rel_id,
        price: urp['price'],
        price_type: urp['price_type'] || 'flat',
        receiving_price: urp['receiving_price'],
        receiving_price_type: urp['receiving_price_type'],
      )
    end

    (@snapshot['user_relationship_request_prices'] || []).each do |urrp|
      UserRelationshipRequestPrice.create!(
        user_id: @name_to_id[urrp['user_name']],
        friend_id: @name_to_id[urrp['friend_user_name']],
        price: urrp['price'],
      )
    end
  end

  def restore_category_sizes
    (@snapshot['category_sizes'] || []).each do |cs|
      CategorySize.create!(
        user_id: @name_to_id[cs['user_name']],
        category_id: Category.find_by(category_name: cs['category_name'])&.id,
        item_unit_id: ItemUnit.find_by(unit_name: cs['unit_name'])&.id,
        quantity: cs['quantity'], price: cs['price'],
      )
    end
  end

  def restore_reviews
    (@snapshot['reviews'] || []).each do |r|
      item_id = r['item_index'] ? @item_ids[r['item_index']] : nil
      Review.create!(
        user_id: @name_to_id[r['user_name']],
        item_id: item_id,
        producer_id: @name_to_id[r['producer_user_name']],
        value: r['value'],
      )
    end
  end
end
