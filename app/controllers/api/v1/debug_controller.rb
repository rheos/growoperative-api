class Api::V1::DebugController < Api::V1::ApiController
  # These endpoints were reachable unauthenticated on production for five
  # months (the debug_api_enabled row was created 2026-04-20 and never
  # changed), returning usernames, who traded with whom, item names, prices
  # and timestamps to anyone who asked. A GlobalSetting is data, not a
  # permission: one row flip re-opened everything, and nothing in the code
  # said so.
  #
  # Now there are two independent gates, and the data row is the weaker one:
  # outside development and test a caller must be an authenticated admin,
  # whatever debug_api_enabled says.
  skip_before_action :authenticate!, if: -> { Rails.env.local? }
  before_action :check_debug_enabled!
  before_action :require_debug_admin!

  private def parse_foaf_extra_data(data)
    return {} if data.blank?
    return data if data.is_a?(Hash)
    JSON.parse(data)
  rescue JSON::ParserError
    {}
  end

  # BalanceUpdate event that's part of a credit-loop cancellation. The parent
  # op's `path` is the full cycle. For each participant in this trustline, the
  # loop also touched their *other* cycle-edge trustline by the same amount —
  # that's the "where did this come from" explanation we show.
  private def build_credloop_row(event, parent, trustline, user_a, user_b, viewer = nil)
    path = parent["path"] || []
    loop_value = parent["value"].to_f
    from_addr = event["from"]  # edge direction this BalanceUpdate represents

    # Resolve "your other cycle neighbor" from the viewer's POV — not user_a's.
    # user_a is whoever has the lower user_id in the trustline; the viewer may
    # be either participant. Without viewer-awareness we'd always surface
    # user_a's other neighbor and get the wrong name when the viewer is user_b.
    viewer ||= user_a
    viewer_addr = viewer.foaf_address
    counterparty_addr = (viewer.id == user_a.id) ? user_b.foaf_address : user_a.foaf_address

    # path wraps, so the last element equals the first.
    # e.g. [bob, bruce, arthur, mary, peter, bob]
    inner = path.size > 1 && path.first == path.last ? path[0..-2] : path
    idx = inner.index(viewer_addr)
    other_addr = nil
    if idx
      prev_addr = inner[(idx - 1) % inner.size]
      next_addr = inner[(idx + 1) % inner.size]
      other_addr = (prev_addr == counterparty_addr) ? next_addr : prev_addr
    end
    other_user = other_addr && User.find_by(foaf_address: other_addr)
    other_name = other_user&.user_name || "another user"
    # Look up the trustline between the VIEWER and this other party so the
    # audit modal can link to it — lets users follow the credloop around the cycle.
    other_trustline_id = other_user && Trustline.between_users(viewer, other_user).first&.id

    # Direction on THIS edge: from user_a's POV, did user_a "send" or "receive"?
    # A BalanceUpdate stores the edge's directional intent in from/to. If user_a
    # is the from_address, user_a was the sender on this hop.
    direction = from_addr == user_a.foaf_address ? "sent" : "received"

    description = "Offset by your balance with #{other_name}"

    {
      transaction: {
        id: event["blockNumber"].to_i,
        trustline_id: trustline.id,
        amount: loop_value,
        description: description,
        transaction_type: "credloop",
        initiated_by_id: nil,
        originating_request_id: nil,
        order_id: nil,
        balance_after: 0.0,
        is_reversed: false,
        created_at: Time.at(event["timestamp"].to_i).iso8601,
        initiated_by_name: nil,
        order_label: nil,
        path_info: {
          hops: path,
          other_user: other_name,
          other_trustline_id: other_trustline_id,
        },
        _direction: direction,
      },
      balance_before: 0.0,
      source_classification: "credloop",
      balance_mismatch: false,
      missing_linkage: false,
    }
  end

  private def build_transfer_row(event, trustline, user_a, user_b)
    extra = parse_foaf_extra_data(event["extraData"])
    is_credloop = extra["credloop_cancellation"].present? || (event["extraData"].to_s.include?("credloop_cancellation"))
    is_adjustment = extra["operation"] == "adjustment"
    order_id = extra["order_id"]
    order_label = extra["order_label"]
    description = extra["description"] || (is_credloop ? "Credit loop cancellation" : nil)
    is_settlement = extra["operation"] == "settlement" ||
                    description.to_s.start_with?("Cash settlement from ")

    classification = if is_credloop
      "credloop"
    elsif is_adjustment
      "adjustment"
    elsif order_id
      "order_settlement"
    else
      "direct_payment"
    end

    transaction_type = if is_adjustment
      "adjustment"
    elsif order_id || is_settlement
      "settlement"
    else
      "payment"
    end

    path = event["path"]
    foaf_sender = event["direction"] == "sent" ? user_a : user_b
    foaf_receiver = event["direction"] == "sent" ? user_b : user_a
    initiator = is_settlement ? foaf_receiver : foaf_sender

    {
      transaction: {
        id: event["blockNumber"].to_i,
        trustline_id: trustline.id,
        amount: event["value"].to_f,
        description: description,
        transaction_type: transaction_type,
        initiated_by_id: initiator.id,
        originating_request_id: nil,
        order_id: order_id,
        balance_after: 0.0,
        is_reversed: false,
        created_at: Time.at(event["timestamp"].to_i).iso8601,
        initiated_by_name: initiator.user_name,
        order_label: order_label,
        path_info: transfer_path_info(path, extra, description),
        _direction: event["direction"]
      },
      balance_before: 0.0,
      source_classification: classification,
      balance_mismatch: false,
      missing_linkage: false
    }
  end

  private def transfer_path_info(path, extra, description)
    info = {}
    info[:hops] = path if path.is_a?(Array) && path.size > 2
    info[:payment_request] = extra["payment_request"] if extra["payment_request"].present?

    if extra["external_payment"].present?
      info[:external_payment] = extra["external_payment"]
    elsif extra["external_payments"].present?
      info[:external_payments] = extra["external_payments"]
    else
      parsed = Foaf::ExternalPayment.metadata_for(description)
      info[:external_payment] = parsed["external_payment"] if parsed["external_payment"]
      info[:external_payments] = parsed["external_payments"] if parsed["external_payments"]
    end

    info.presence
  end

  private def build_trustline_update_row(event, trustline, user_a, user_b)
    # FOAF stores creditlineGiven/Received from the ORIGINATING user's POV.
    # user_events returns events from both sides of the bilateral update, so
    # "received" events arrive with values flipped from user_a's perspective.
    # Normalize so "given" / "received" are always from user_a's side.
    raw_given = event["creditlineGiven"].to_f
    raw_received = event["creditlineReceived"].to_f
    if event["direction"] == "received"
      given = raw_received
      received = raw_given
    else
      given = raw_given
      received = raw_received
    end
    initiator = event["direction"] == "sent" ? user_a : user_b

    {
      transaction: {
        id: event["blockNumber"].to_i,
        trustline_id: trustline.id,
        amount: 0.0,
        description: "Limits updated (given: $#{given}, received: $#{received})",
        transaction_type: "adjustment",
        initiated_by_id: initiator.id,
        originating_request_id: nil,
        order_id: nil,
        balance_after: 0.0,
        is_reversed: false,
        created_at: Time.at(event["timestamp"].to_i).iso8601,
        initiated_by_name: initiator.user_name,
        order_label: nil,
        path_info: nil,
        _direction: event["direction"]
      },
      balance_before: 0.0,
      source_classification: "adjustment",
      balance_mismatch: false,
      missing_linkage: false
    }
  end

  # Development and test stay open: the `debug-api` skill and the bin/ dev
  # scripts call these without a token, and there is no real data to leak.
  private def require_debug_admin!
    return if Rails.env.local?
    return if current_user&.is_admin?

    render json: { error: 'Debug API requires an admin' }, status: :forbidden
  end

  private def check_debug_enabled!
    return if Rails.env.local?
    setting = GlobalSetting.find_by(setting: 'debug_api_enabled')
    unless setting&.value == 1
      render json: { error: 'Debug API is disabled' }, status: 403
    end
  end

  private def settlement_amount_for(order)
    settled_transaction = TrustlineTransaction.where(order_id: order.id)
      .where.not(transaction_type: 'reversal')
      .order(created_at: :desc)
      .first
    return settled_transaction.amount.to_f if settled_transaction

    order.settlement_amount.to_f
  end

  # GET /v1/debug/invariants
  # Runs every registered data-integrity check against the current DB state
  # and reports pass/fail. Used by the end-to-end trade test; also useful
  # from curl/browser console when debugging.
  def invariants
    render json: InvariantsService.run
  end

  # GET /v1/debug/order/:id
  def order
    o = Order.find(params[:id])
    buyer = User.find(o.user_id)
    seller = User.find(o.friend_id)

    items = o.item_requests.map do |ir|
      inv = ir.request_contract&.inventory
      {
        item_request_id: ir.id,
        status: ir.status,
        user: User.find(ir.user_id).user_name,
        friend: User.find(ir.friend_id).user_name,
        price: ir.price,
        sent: ir.sent,
        order_id: ir.order_id,
        accepted_at: ir.accepted_at,
        shipped_at: ir.shipped_at,
        signed_at: ir.signed_at,
        request_contract_id: ir.request_contract_id,
        contract_status: ir.request_contract&.status,
        contract_quantity: ir.request_contract&.quantity,
        contract_steps: ir.request_contract&.steps,
        contract_current_step: ir.request_contract&.current_step,
        inventory_id: inv&.id,
        item_name: inv&.item&.name,
        item_owner: inv ? User.find(inv.user_id).user_name : nil,
        inventory_status: inv&.status,
        inventory_quantity: inv&.quantity
      }
    end

    render json: {
      order: {
        id: o.id,
        label: o.order_label,
        order_status: o.order_status,
        settlement_amount: settlement_amount_for(o),
        buyer: buyer.user_name,
        buyer_id: o.user_id,
        seller: seller.user_name,
        seller_id: o.friend_id,
        settlement_type: o.settlement_type,
        settlement_status: o.settlement_status,
        settlement_proposed_by: o.settlement_proposed_by,
        created_at: o.created_at,
        shipped_on: o.shipped_on,
        signed_on: o.signed_on
      },
      item_requests: items
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Order #{params[:id]} not found" }, status: 404
  end

  # GET /v1/debug/requests?item_name=Hot+Peppers or ?user=bruce or ?inventory_id=123
  def requests
    scope = ItemRequest.all.includes(:request_contract, :user, :friend)

    if params[:user].present?
      user = User.find_by(user_name: params[:user])
      return render(json: { error: "User '#{params[:user]}' not found" }, status: 404) unless user
      scope = scope.where('user_id = ? OR friend_id = ?', user.id, user.id)
    end

    if params[:inventory_id].present?
      scope = scope.joins(:request_contract).where(request_contracts: { inventory_id: params[:inventory_id] })
    end

    if params[:item_name].present?
      scope = scope.joins(request_contract: { inventory: :item }).where('items.name LIKE ?', "%#{params[:item_name]}%")
    end

    if params[:status].present?
      scope = scope.where(status: ItemRequest.statuses[params[:status]])
    end

    if params[:order_id].present?
      scope = scope.where(order_id: params[:order_id])
    end

    scope = scope.order(created_at: :desc).limit(params.fetch(:limit, 50).to_i)

    results = scope.map do |ir|
      inv = ir.request_contract&.inventory
      {
        item_request_id: ir.id,
        status: ir.status,
        user: ir.user.user_name,
        friend: ir.friend.user_name,
        price: ir.price,
        sent: ir.sent,
        order_id: ir.order_id,
        request_contract_id: ir.request_contract_id,
        contract_status: ir.request_contract&.status,
        contract_quantity: ir.request_contract&.quantity,
        inventory_id: inv&.id,
        item_name: inv&.item&.name,
        inventory_status: inv&.status,
        created_at: ir.created_at
      }
    end

    render json: { count: results.size, requests: results }
  end

  # GET /v1/debug/items/:username
  # Returns available items from this user's perspective (what they'd see on their dashboard)
  def items
    u = User.find_by!(user_name: params[:username])
    range_degree = (params[:range_degree] || 2).to_i

    relationships = Relationship.where(
      "(user_id=#{u.id} AND friend_actions_state < 2 AND (actions_state = 0 OR actions_state = 2)) " \
      "OR (friend_id=#{u.id} AND actions_state < 2 AND (friend_actions_state = 0 OR friend_actions_state = 2))"
    )

    users = relationships.pluck(:user_id, :friend_id).flatten.uniq
    users = users.select { |id| !User.find(id).only_consumer_retailer? }
    users.delete(u.id)

    return render(json: { count: 0, items: [] }) if users.empty?

    inventories = Inventory.where(
      "inventories.user_id IN (?) AND inventories.quantity > 0 AND inventories.status = 1 AND inventories.user_id != ?",
      users, u.id
    ).distinct.includes(item: [:item_unit])

    result = inventories.map do |inv|
      price = if inv.apply_first_hop_markup?
                helpers.get_relation_price(inv.user_id, u.id).apply_to(inv.price || 0)
              else
                inv.price.to_f
              end
      {
        inventory_id: inv.id,
        item_name: inv.item.name,
        owner: User.find(inv.user_id).user_name,
        quantity: inv.quantity.to_f,
        base_price: inv.price.to_f,
        display_price: price,
        category: inv.item.category&.category_name,
        status: inv.status
      }
    end

    render json: { count: result.size, items: result.sort_by { |i| i[:display_price] } }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User '#{params[:username]}' not found" }, status: 404
  end

  # POST /v1/debug/create_request
  # Creates a request chain as a user, using the real BFS pathfinding + per-hop pricing.
  # Params: user_name, inventory_id, quantity
  def create_request
    user = User.find_by!(user_name: params[:user_name])
    inventory = Inventory.find(params[:inventory_id])
    quantity = params[:quantity].to_f

    if inventory.user_id == user.id
      return render json: { error: "#{user.user_name} owns this inventory" }, status: 400
    end

    if quantity <= 0 || quantity > inventory.quantity
      return render json: { error: "Invalid quantity (available: #{inventory.quantity})" }, status: 400
    end

    # BFS pathfinding — same algorithm as ItemRequestsController#create
    max_depth = 5
    contacts = [{ user_id: user.id, path: [] }]
    shortest = { total: BigDecimal::INFINITY, path: [], prices: [] }

    while contacts.size > 0
      contact = contacts.shift

      if contact[:user_id] == inventory.user_id
        path = contact[:path] + [inventory.user_id]
        prices = debug_request_chain_prices(inventory, path)
        total = prices.last || inventory.price.to_f
        shortest = { total: total, path: path, prices: prices.reverse } if total < shortest[:total]
      elsif contact[:path].size < max_depth
        rels = Relationship.where("user_id = #{contact[:user_id]} OR friend_id = #{contact[:user_id]}")
        if rels.size > 0
          rels.pluck(:user_id, :friend_id).flatten!.uniq
            .select { |id| !User.find(id).only_consumer_retailer? }
            .each do |relation_id|
              next if relation_id == contact[:user_id]
              next if contact[:path].include?(relation_id)

              contacts.push({
                user_id: relation_id,
                path: contact[:path] + [contact[:user_id]],
              })
            end
        end
      end
    end

    if shortest[:total] == BigDecimal::INFINITY || shortest[:path].size <= 1
      return render json: { error: "No path found from #{user.user_name} to #{inventory.item.name}" }, status: 400
    end

    chain_prices = debug_request_chain_prices(inventory, shortest[:path]).reverse

    # Create contract + request chain
    rc = RequestContract.create!(
      user_id: user.id,
      inventory_id: inventory.id,
      item_id: inventory.item_id,
      quantity: quantity,
      steps: chain_prices.size,
    )

    created_requests = []

    chain_prices.each_with_index do |price, index|
      ir = ItemRequest.create!(
        request_contract_id: rc.id,
        user_id: shortest[:path][index],
        friend_id: shortest[:path][index + 1],
        price: price,
        status: :pending,
        sent: shortest[:path][index] == user.id ? 1 : 0,
        step: chain_prices.size - index,
      )
      created_requests << {
        item_request_id: ir.id,
        user: User.find(ir.user_id).user_name,
        friend: User.find(ir.friend_id).user_name,
        price: ir.price.to_f,
        step: ir.step,
        status: ir.status,
      }
    end

    render json: {
      message: "Request chain created",
      contract_id: rc.id,
      item: inventory.item.name,
      quantity: quantity,
      chain: created_requests,
    }
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  end

  # POST /v1/debug/accept_request/:id
  # Accepts a request as a user.
  # Params: user_name
  def accept_request
    user = User.find_by!(user_name: params[:user_name])
    ir = ItemRequest.find(params[:id])

    unless ir.friend_id == user.id || (ir.status == "reserved" && ir.user_id == user.id)
      return render json: { error: "#{user.user_name} is not the recipient of request #{ir.id}" }, status: 403
    end

    unless ir.pending? || ir.status == "reserved"
      return render json: { error: "Request #{ir.id} is #{ir.status}, not pending" }, status: 406
    end

    unless ir.request_contract.pending?
      return render json: { error: "Contract #{ir.request_contract_id} is #{ir.request_contract.status}, not pending" }, status: 406
    end

    result = ir.accept_request
    if result == true
      render json: {
        message: "Request #{ir.id} accepted",
        item_request_id: ir.id,
        user: User.find(ir.user_id).user_name,
        friend: User.find(ir.friend_id).user_name,
        status: ir.reload.status,
      }
    else
      render json: { error: "Accept failed", details: result }, status: 500
    end
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: 404
  end

  # GET /v1/debug/user/:username
  def user
    u = User.find_by!(user_name: params[:username])
    orders_as_buyer = Order.where(user_id: u.id).order(created_at: :desc).limit(10)
    orders_as_seller = Order.where(friend_id: u.id).order(created_at: :desc).limit(10)

    render json: {
      user: { id: u.id, user_name: u.user_name, email: u.email },
      orders_as_buyer: orders_as_buyer.map { |o|
        { id: o.id, label: o.order_label, status: o.order_status, counterparty: User.find(o.friend_id).user_name,
          settlement_status: o.settlement_status, settlement_amount: settlement_amount_for(o), created_at: o.created_at }
      },
      orders_as_seller: orders_as_seller.map { |o|
        { id: o.id, label: o.order_label, status: o.order_status, counterparty: User.find(o.user_id).user_name,
          settlement_status: o.settlement_status, settlement_amount: settlement_amount_for(o), created_at: o.created_at }
      },
      recent_item_requests: ItemRequest.where('user_id = ? OR friend_id = ?', u.id, u.id)
        .order(created_at: :desc).limit(10).map { |ir|
          { id: ir.id, status: ir.status, user: User.find(ir.user_id).user_name,
            friend: User.find(ir.friend_id).user_name, order_id: ir.order_id,
            item: ir.request_contract&.inventory&.item&.name }
        }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "User '#{params[:username]}' not found" }, status: 404
  end

  # GET /v1/debug/foaf/reconcile
  # Compare all trustline state between the app and FOAF protocol.
  def foaf_reconcile
    unless Foaf::Config.foaf_write_enabled?
      return render json: { error: "FOAF publishing is not enabled" }, status: 400
    end

    render json: Foaf::AuditService.reconcile_trustlines(Trustline.active)
  end

  # GET /v1/debug/foaf/events/:trustline_id
  # Returns FOAF protocol events for this trustline, mapped to the same
  # AuditLedgerRow shape the app uses, so the audit report can render them
  # with the same component.
  def foaf_events
    unless Foaf::Config.foaf_write_enabled?
      return render json: { error: "FOAF publishing is not enabled" }, status: 400
    end

    trustline = Trustline.find(params[:trustline_id])
    user_a = User.find(trustline.user_a_id)
    user_b = User.find(trustline.user_b_id)

    unless user_a.foaf_address.present? && user_b.foaf_address.present?
      return render json: { rows: [], warning: "One or both users have no FOAF address" }
    end

    client = Foaf::Client.new
    networks = client.networks
    unless networks&.any?
      return render json: { error: "No FOAF network found" }, status: 400
    end
    network_address = networks.first["address"]

    events = client.user_events(
      network_address: network_address,
      user_address: user_a.foaf_address
    ) || []

    # Only events where the counterparty is user_b
    relevant = events.select { |e| e["counterParty"] == user_b.foaf_address }

    rows = []

    # Publisher emits TWO update_trustline API calls per logical limit change
    # (one from each side of the bilateral agreement), which FOAF records as
    # two TrustlineUpdate events at the same timestamp but from opposite POVs.
    # After normalizing to user_a's perspective in build_trustline_update_row,
    # the pair is redundant — dedupe by (timestamp, normalized given/received).
    seen_update_keys = Set.new

    relevant.each do |e|
      case e["type"]
      when "Transfer"
        rows << build_transfer_row(e, trustline, user_a, user_b)
      when "TrustlineUpdate"
        raw_given = e["creditlineGiven"].to_f
        raw_received = e["creditlineReceived"].to_f
        norm_given = e["direction"] == "received" ? raw_received : raw_given
        norm_received = e["direction"] == "received" ? raw_given : raw_received
        key = [e["timestamp"], norm_given, norm_received]
        next if seen_update_keys.include?(key)
        seen_update_keys << key
        rows << build_trustline_update_row(e, trustline, user_a, user_b)
      end
    end

    # Credloop cancellations that passed through this trustline edge. The
    # Transfer event for a credloop has from == to == the initiator, so it
    # won't appear under either participant's counterparty filter. But the
    # BalanceUpdate on this specific edge IS scoped correctly via the per-
    # trustline events endpoint. For each BalanceUpdate whose parent op is
    # a self-transfer (from == to), render a credloop row.
    tl_events = client.trustline_events(
      network_address: network_address,
      user_address: user_a.foaf_address,
      counter_party_address: user_b.foaf_address,
    ) || []
    tl_events.each do |e|
      next unless e["type"] == "BalanceUpdate"
      parent = e["parentOp"]
      next unless parent && parent["from"] == parent["to"]
      rows << build_credloop_row(e, parent, trustline, user_a, user_b, current_user)
    end

    # FOAF returned descending; reverse to ascending to build running balance
    rows.sort_by! { |r| [r[:transaction][:created_at], r[:transaction][:id]] }

    # Running balance from user_a's perspective using direction:
    # user_a sent  -> user_a owes more -> balance += value  (app convention: + = user_a owes user_b)
    # user_a received -> user_a owes less -> balance -= value
    running = 0.0
    rows.each_with_index do |row, i|
      tx = row[:transaction]
      row[:balance_before] = running
      # Zero-amount rows (trustline limit updates) are balance-neutral; anything
      # with a real amount — including record_debt / record_receipt adjustments
      # — moves the balance by `value` in the transfer's direction.
      if tx[:amount].to_f == 0
        tx[:balance_after] = running
      else
        delta = tx[:_direction] == 'sent' ? tx[:amount] : -tx[:amount]
        running += delta
        tx[:balance_after] = running
      end
      tx.delete(:_direction)
    end

    render json: { rows: rows.reverse } # back to descending for display
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Trustline #{params[:trustline_id]} not found" }, status: 404
  end

  # GET /v1/debug/subnet_applications?status=pending
  # Lists subnet applications. Optional ?status= filter (pending/approved/rejected).
  def subnet_applications
    scope = SubnetApplication.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?

    render json: {
      count: scope.count,
      applications: scope.map { |a|
        {
          id: a.id,
          status: a.status,
          community_name: a.community_name,
          location: a.location,
          contact_name: a.contact_name,
          contact_email: a.contact_email,
          description: a.description,
          created_at: a.created_at,
          reviewed_by: a.reviewed_by&.user_name,
        }
      }
    }
  end

  # GET /v1/debug/foaf/status
  # Quick check: is FOAF reachable and what's its state?
  def foaf_status
    unless Foaf::Config.foaf_write_enabled?
      return render json: {
        foaf_write_enabled: false,
        # Temporary response compatibility for the existing admin frontend.
        shadow_mode: false
      }
    end

    client = Foaf::Client.new
    version = begin
      uri = URI("#{Foaf::Config.api_url}/api/v1/version")
      Net::HTTP.get(uri)
    rescue => e
      nil
    end

    networks = client.networks

    render json: {
      foaf_write_enabled: true,
      # Temporary response compatibility for the existing admin frontend.
      shadow_mode: true,
      foaf_url: Foaf::Config.api_url,
      foaf_reachable: version.present?,
      foaf_version: version,
      networks: networks&.size || 0,
      users_with_foaf_address: User.where.not(foaf_address: nil).count,
      users_total: User.count
    }
  end

  def debug_request_chain_prices(inventory, buyer_to_owner_path)
    owner_to_buyer_path = buyer_to_owner_path.reverse
    prices = []
    running_price = inventory.price.to_f

    owner_to_buyer_path.each_cons(2).with_index do |(seller_id, buyer_id), index|
      unless index.zero? && !inventory.apply_first_hop_markup?
        running_price = helpers.get_relation_price(seller_id, buyer_id).apply_to(running_price)
      end
      prices << running_price
    end

    prices
  end
end
