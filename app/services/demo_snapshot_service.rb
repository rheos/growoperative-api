class DemoSnapshotService
  CORE_DEMO_USERNAMES = %w[bob dianna peter paul sara mary bruce arthur clark oliver barry mark john].freeze
  SNAPSHOTS_DIR = Rails.root.join('db', 'demo_snapshots')
  # Legacy single-file path (used as fallback)
  LEGACY_PATH = Rails.root.join('db', 'demo_snapshot.json')

  def initialize(name: nil, include_requests: true)
    @name = name
    @include_requests = include_requests
  end

  def capture
    FileUtils.mkdir_p(SNAPSHOTS_DIR)

    demo_users = User.where(user_name: CORE_DEMO_USERNAMES)
    demo_ids = demo_users.pluck(:id)
    demo_id_to_name = demo_users.pluck(:id, :user_name).to_h

    snapshot = {
      captured_at: Time.current.iso8601,
      name: @name || 'default',
      include_requests: @include_requests,
      core_usernames: CORE_DEMO_USERNAMES,
      users: snapshot_users(demo_users),
      user_groups: snapshot_user_groups(demo_ids, demo_id_to_name),
      relationships: snapshot_relationships(demo_ids, demo_id_to_name),
      trustlines: snapshot_trustlines(demo_ids, demo_id_to_name),
      trustline_transactions: snapshot_trustline_transactions(demo_ids, demo_id_to_name),
      items: snapshot_items(demo_ids, demo_id_to_name),
      inventories: snapshot_inventories(demo_ids, demo_id_to_name),
      unit_options: snapshot_unit_options(demo_ids),
      user_category_prices: snapshot_user_category_prices(demo_ids, demo_id_to_name),
      user_relationship_prices: snapshot_user_relationship_prices(demo_ids, demo_id_to_name),
      user_relationship_request_prices: snapshot_user_relationship_request_prices(demo_ids, demo_id_to_name),
      category_sizes: snapshot_category_sizes(demo_ids, demo_id_to_name),
      reviews: snapshot_reviews(demo_ids, demo_id_to_name),
    }

    if @include_requests
      snapshot[:request_contracts] = snapshot_request_contracts(demo_ids, demo_id_to_name)
      snapshot[:item_requests] = snapshot_item_requests(demo_ids, demo_id_to_name)
      snapshot[:orders] = snapshot_orders(demo_ids, demo_id_to_name)
    else
      snapshot[:request_contracts] = []
      snapshot[:item_requests] = []
      snapshot[:orders] = []
    end

    filename = sanitize_name(@name || 'default') + '.json'
    File.write(SNAPSHOTS_DIR.join(filename), JSON.pretty_generate(snapshot))
    snapshot
  end

  # List all saved snapshots (name, date, counts)
  def self.list
    dir = SNAPSHOTS_DIR
    files = Dir.glob(dir.join('*.json')).sort_by { |f| File.mtime(f) }.reverse

    # Include legacy file if it exists and no named snapshots contain its data
    if File.exist?(LEGACY_PATH) && !files.any? { |f| File.basename(f) == 'default.json' }
      files.unshift(LEGACY_PATH.to_s)
    end

    files.map do |path|
      snap = JSON.parse(File.read(path))
      {
        name: snap['name'] || File.basename(path, '.json'),
        filename: File.basename(path),
        captured_at: snap['captured_at'],
        include_requests: snap['include_requests'] != false,
        items: (snap['items'] || []).size,
        orders: (snap['orders'] || []).size,
        item_requests: (snap['item_requests'] || []).size,
        relationships: (snap['relationships'] || []).size,
      }
    end
  end

  # Load a snapshot by name
  def self.load(name)
    filename = name.gsub(/[^a-zA-Z0-9_\-]/, '_') + '.json'
    path = SNAPSHOTS_DIR.join(filename)

    # Fallback to legacy path
    unless File.exist?(path)
      if name == 'default' && File.exist?(LEGACY_PATH)
        return JSON.parse(File.read(LEGACY_PATH))
      end
      raise "Snapshot '#{name}' not found"
    end

    JSON.parse(File.read(path))
  end

  private

  def sanitize_name(name)
    name.gsub(/[^a-zA-Z0-9_\-]/, '_').downcase
  end

  private

  def snapshot_users(users)
    users.map do |u|
      {
        user_name: u.user_name,
        name: u.name,
        nickname: u.nickname,
        depth: u.depth,
        invite_limit: u.invite_limit,
        invitation_limit: u.invitation_limit,
        invitations_count: u.invitations_count,
        parent_user_name: u.parent_id ? User.find_by(id: u.parent_id)&.user_name : nil,
      }
    end
  end

  def snapshot_user_groups(demo_ids, id_to_name)
    UserGroup.where(user_id: demo_ids).map do |ug|
      { user_name: id_to_name[ug.user_id], group_label: ug.group_label }
    end
  end

  def snapshot_relationships(demo_ids, id_to_name)
    Relationship.where(user_id: demo_ids, friend_id: demo_ids).map do |r|
      {
        user_name: id_to_name[r.user_id],
        friend_user_name: id_to_name[r.friend_id],
        status: r.status,
        action_user_name: id_to_name[r.action_user_id],
        user_label: r.user_label,
        friend_label: r.friend_label,
      }
    end
  end

  def snapshot_trustlines(demo_ids, id_to_name)
    Trustline.where(user_a_id: demo_ids, user_b_id: demo_ids).map do |t|
      {
        user_a_name: id_to_name[t.user_a_id],
        user_b_name: id_to_name[t.user_b_id],
        credit_limit_a_to_b: t.credit_limit_a_to_b.to_f,
        credit_limit_b_to_a: t.credit_limit_b_to_a.to_f,
        current_balance: t.current_balance.to_f,
        is_active: t.is_active,
        notes: t.notes,
      }
    end
  end

  def snapshot_trustline_transactions(demo_ids, id_to_name)
    trustline_ids = Trustline.where(user_a_id: demo_ids, user_b_id: demo_ids).pluck(:id)
    TrustlineTransaction.where(trustline_id: trustline_ids).map do |tt|
      {
        trustline_user_a_name: id_to_name[Trustline.find(tt.trustline_id).user_a_id],
        trustline_user_b_name: id_to_name[Trustline.find(tt.trustline_id).user_b_id],
        amount: tt.amount.to_f,
        description: tt.description,
        transaction_type: tt.transaction_type,
        initiated_by_name: id_to_name[tt.initiated_by_id],
        balance_after: tt.balance_after.to_f,
        is_reversed: tt.is_reversed,
        path_info: tt.path_info,
        created_at: tt.created_at&.iso8601,
      }
    end
  end

  def snapshot_items(demo_ids, id_to_name)
    Item.where(user_id: demo_ids).map do |item|
      {
        original_id: item.id,
        user_name: id_to_name[item.user_id],
        category_name: item.category&.category_name,
        item_name_value: item.item_name&.name,
        grade_name: item.grade&.name,
        unit_name: item.item_unit&.unit_name,
        quantity: item.quantity,
        price: item.price.to_f,
        date_available: item.date_available&.iso8601,
        organic: item.organic,
        name: item.name,
        avatars_raw: item.read_attribute_before_type_cast(:avatars),
        producer_user_name: id_to_name[item.producer_id],
      }
    end
  end

  def snapshot_inventories(demo_ids, id_to_name)
    Inventory.where(user_id: demo_ids).map do |inv|
      {
        user_name: id_to_name[inv.user_id],
        item_index: Item.where(user_id: demo_ids).pluck(:id).index(inv.item_id),
        quantity: inv.quantity,
        price: inv.price.to_f,
        status: inv.status,
        avatars_raw: inv.read_attribute_before_type_cast(:avatars),
        description: inv.description,
        ref_price: inv.ref_price.to_f,
      }
    end
  end

  def snapshot_unit_options(demo_ids)
    inventory_ids = Inventory.where(user_id: demo_ids).pluck(:id)
    UnitOption.where(inventory_id: inventory_ids).map do |uo|
      {
        inventory_index: inventory_ids.index(uo.inventory_id),
        unit_name: ItemUnit.find_by(id: uo.item_unit_id)&.unit_name,
        price: uo.price.to_f,
        quantity: uo.quantity,
      }
    end
  end

  def snapshot_request_contracts(demo_ids, id_to_name)
    RequestContract.where(user_id: demo_ids).map do |rc|
      {
        user_name: id_to_name[rc.user_id],
        item_index: Item.where(user_id: demo_ids).pluck(:id).index(rc.item_id),
        inventory_index: Inventory.where(user_id: demo_ids).pluck(:id).index(rc.inventory_id),
        quantity: rc.quantity,
        status: rc.status,
        steps: rc.steps,
        current_step: rc.current_step,
        unit: rc.unit,
      }
    end
  end

  def snapshot_item_requests(demo_ids, id_to_name)
    rc_ids = RequestContract.where(user_id: demo_ids).pluck(:id)
    ItemRequest.where(user_id: demo_ids).or(ItemRequest.where(friend_id: demo_ids)).map do |ir|
      {
        user_name: id_to_name[ir.user_id],
        friend_user_name: id_to_name[ir.friend_id],
        request_contract_index: rc_ids.index(ir.request_contract_id),
        price: ir.price.to_f,
        status: ir.status,
        step: ir.step,
        sent: ir.sent,
        accepted_at: ir.accepted_at&.iso8601,
        shipped_at: ir.shipped_at&.iso8601,
        signed_at: ir.signed_at&.iso8601,
      }
    end
  end

  def snapshot_orders(demo_ids, id_to_name)
    Order.where(user_id: demo_ids).or(Order.where(friend_id: demo_ids)).map do |o|
      {
        user_name: id_to_name[o.user_id],
        friend_user_name: id_to_name[o.friend_id],
        order_label: o.order_label,
        order_status: o.order_status,
      }
    end
  end

  def snapshot_user_category_prices(demo_ids, id_to_name)
    UserCategoryPrice.where(user_id: demo_ids).map do |ucp|
      {
        user_name: id_to_name[ucp.user_id],
        category_name: Category.find_by(id: ucp.category_id)&.category_name,
        price: ucp.price.to_f,
      }
    end
  end

  def snapshot_user_relationship_prices(demo_ids, id_to_name)
    UserRelationshipPrice.where(user_id: demo_ids).map do |urp|
      {
        user_name: id_to_name[urp.user_id],
        friend_user_name: id_to_name[urp.friend_id],
        category_name: Category.find_by(id: urp.category_id)&.category_name,
        price: urp.price.to_f,
        receiving_price: urp.try(:receiving_price)&.to_f,
        receiving_price_type: urp.try(:receiving_price_type),
      }
    end
  end

  def snapshot_user_relationship_request_prices(demo_ids, id_to_name)
    UserRelationshipRequestPrice.where(user_id: demo_ids).map do |urrp|
      {
        user_name: id_to_name[urrp.user_id],
        friend_user_name: id_to_name[urrp.friend_id],
        price: urrp.price.to_f,
      }
    end
  end

  def snapshot_category_sizes(demo_ids, id_to_name)
    CategorySize.where(user_id: demo_ids).map do |cs|
      {
        user_name: id_to_name[cs.user_id],
        category_name: Category.find_by(id: cs.category_id)&.category_name,
        unit_name: ItemUnit.find_by(id: cs.item_unit_id)&.unit_name,
        quantity: cs.quantity,
        price: cs.price.to_f,
      }
    end
  end

  def snapshot_reviews(demo_ids, id_to_name)
    Review.where(user_id: demo_ids).map do |r|
      {
        user_name: id_to_name[r.user_id],
        item_index: Item.where(user_id: demo_ids).pluck(:id).index(r.item_id),
        producer_user_name: id_to_name[r.producer_id],
        value: r.value,
      }
    end
  end
end
