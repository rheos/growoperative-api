class Api::V1::DebugController < Api::V1::ApiController
  skip_before_action :authenticate!
  before_action :check_debug_enabled!

  private def parse_foaf_extra_data(data)
    return {} if data.blank?
    return data if data.is_a?(Hash)
    JSON.parse(data)
  rescue JSON::ParserError
    {}
  end

  private def build_transfer_row(event, trustline, user_a, user_b)
    extra = parse_foaf_extra_data(event["extraData"])
    is_credloop = extra["credloop_cancellation"].present? || (event["extraData"].to_s.include?("credloop_cancellation"))
    order_id = extra["order_id"]
    order_label = extra["order_label"]
    description = extra["description"] || (is_credloop ? "Credit loop cancellation" : nil)

    classification = if is_credloop
      "credloop"
    elsif order_id
      "order_settlement"
    else
      "direct_payment"
    end

    transaction_type = order_id ? "settlement" : "payment"

    path = event["path"]
    initiator = event["direction"] == "sent" ? user_a : user_b

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
        path_info: path.is_a?(Array) && path.size > 2 ? { hops: path } : nil,
        _direction: event["direction"]
      },
      balance_before: 0.0,
      source_classification: classification,
      balance_mismatch: false,
      missing_linkage: false
    }
  end

  private def build_trustline_update_row(event, trustline, user_a, user_b)
    given = event["creditlineGiven"].to_f
    received = event["creditlineReceived"].to_f
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

  private def check_debug_enabled!
    return if Rails.env.development? || Rails.env.test?
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

    order.send(:settlement_amount).to_f
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
      price = if inv.producer_owns?
                inv.price.to_f
              else
                (inv.price || 0).to_f + helpers.get_relation_price(inv.user_id, u.id).to_f
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
    contacts = [{ user_id: user.id, path: [], prices: [], total: 0, route_price: 0 }]
    shortest = { total: BigDecimal::INFINITY, path: [], prices: [] }
    checked_contacts = {}

    while contacts.size > 0
      contact = contacts.shift
      checked_contacts[contact[:user_id]] = contact[:total]

      if contact[:user_id] == inventory.user_id
        unless inventory.producer_owns?
          contact[:total] += helpers.get_relation_price(inventory.user_id, contact[:path].last)
        end
        shortest = contact if contact[:total] < shortest[:total]
      elsif contact[:path].size < max_depth
        rels = Relationship.where("user_id = #{contact[:user_id]} OR friend_id = #{contact[:user_id]}")
        if rels.size > 0
          rels.pluck(:user_id, :friend_id).flatten!.uniq
            .select { |id| !User.find(id).only_consumer_retailer? }
            .each do |relation_id|
              next if relation_id == contact[:user_id]
              total = contact[:total] + contact[:route_price]
              if total < shortest[:total] &&
                (checked_contacts[relation_id].nil? || total < checked_contacts[relation_id])
                contacts.push({
                  user_id: relation_id,
                  path: contact[:path] + [contact[:user_id]],
                  prices: contact[:prices] + [total],
                  total: total,
                  route_price: helpers.get_relation_price(relation_id, contact[:user_id]),
                })
              end
            end
        end
      end
    end

    if shortest[:total] == BigDecimal::INFINITY || shortest[:path].empty?
      return render json: { error: "No path found from #{user.user_name} to #{inventory.item.name}" }, status: 400
    end

    # Create contract + request chain
    rc = RequestContract.create!(
      user_id: user.id,
      inventory_id: inventory.id,
      item_id: inventory.item_id,
      quantity: quantity,
      steps: shortest[:prices].size,
    )

    shortest[:path] << inventory.user_id
    final_price = inventory.price + shortest[:total]
    created_requests = []

    shortest[:prices].each_with_index do |price, index|
      ir = ItemRequest.create!(
        request_contract_id: rc.id,
        user_id: shortest[:path][index],
        friend_id: shortest[:path][index + 1],
        price: final_price - price,
        status: :pending,
        sent: shortest[:path][index] == user.id ? 1 : 0,
        step: shortest[:prices].size - index,
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
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
    end

    client = Foaf::Client.new
    networks = client.networks
    unless networks&.any?
      return render json: { error: "No FOAF network found" }, status: 400
    end
    network_address = networks.first["address"]

    results = []

    Trustline.where(is_active: true).each do |tl|
      user_a = User.find(tl.user_a_id)
      user_b = User.find(tl.user_b_id)

      row = {
        trustline_id: tl.id,
        user_a: user_a.user_name,
        user_b: user_b.user_name,
        app: {
          credit_limit_a_to_b: tl.credit_limit_a_to_b.to_f,
          credit_limit_b_to_a: tl.credit_limit_b_to_a.to_f,
          balance: tl.current_balance.to_f
        },
        foaf: nil,
        match: nil,
        discrepancies: []
      }

      # Look up FOAF state
      if user_a.foaf_address.present?
        foaf_trustlines = client.user_trustlines(
          network_address: network_address,
          user_address: user_a.foaf_address
        )

        if foaf_trustlines
          foaf_tl = foaf_trustlines.find { |ft| ft["counterParty"] == user_b.foaf_address }

          if foaf_tl
            # Map FOAF fields back to app semantics for comparison
            # FOAF "given" (from user_a perspective) = app credit_limit_b_to_a
            # FOAF "received" (from user_a perspective) = app credit_limit_a_to_b
            # FOAF balance (positive = B owes A) = -1 * app balance (positive = A owes B)
            foaf_limit_a_to_b = foaf_tl["received"]
            foaf_limit_b_to_a = foaf_tl["given"]
            foaf_balance = -foaf_tl["balance"]  # negate to match app convention

            row[:foaf] = {
              credit_limit_a_to_b: foaf_limit_a_to_b,
              credit_limit_b_to_a: foaf_limit_b_to_a,
              balance: foaf_balance,
              raw: {
                given: foaf_tl["given"],
                received: foaf_tl["received"],
                balance: foaf_tl["balance"]
              }
            }

            # Compare
            if tl.credit_limit_a_to_b.to_f != foaf_limit_a_to_b
              row[:discrepancies] << {
                field: "credit_limit_a_to_b",
                app: tl.credit_limit_a_to_b.to_f,
                foaf: foaf_limit_a_to_b
              }
            end

            if tl.credit_limit_b_to_a.to_f != foaf_limit_b_to_a
              row[:discrepancies] << {
                field: "credit_limit_b_to_a",
                app: tl.credit_limit_b_to_a.to_f,
                foaf: foaf_limit_b_to_a
              }
            end

            if tl.current_balance.to_f != foaf_balance
              row[:discrepancies] << {
                field: "balance",
                app: tl.current_balance.to_f,
                foaf: foaf_balance
              }
            end

            row[:match] = row[:discrepancies].empty?
          else
            row[:discrepancies] << { field: "trustline", error: "Not found in FOAF" }
            row[:match] = false
          end
        else
          row[:discrepancies] << { field: "api", error: "FOAF API call failed" }
          row[:match] = false
        end
      else
        row[:discrepancies] << { field: "identity", error: "#{user_a.user_name} has no FOAF address" }
        row[:match] = false
      end

      results << row
    end

    summary = {
      total: results.size,
      matches: results.count { |r| r[:match] == true },
      discrepancies: results.count { |r| r[:match] == false },
      unlinked: results.count { |r| r[:match].nil? }
    }

    render json: { summary: summary, trustlines: results }
  end

  # GET /v1/debug/foaf/events/:trustline_id
  # Returns FOAF protocol events for this trustline, mapped to the same
  # AuditLedgerRow shape the app uses, so the audit report can render them
  # with the same component.
  def foaf_events
    unless Foaf::Config.shadow_mode?
      return render json: { error: "FOAF shadow mode is not enabled" }, status: 400
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

    relevant.each do |e|
      case e["type"]
      when "Transfer"
        rows << build_transfer_row(e, trustline, user_a, user_b)
      when "TrustlineUpdate"
        rows << build_trustline_update_row(e, trustline, user_a, user_b)
      end
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
      if tx[:transaction_type] == 'adjustment'
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

  # GET /v1/debug/foaf/status
  # Quick check: is FOAF reachable and what's its state?
  def foaf_status
    unless Foaf::Config.shadow_mode?
      return render json: { shadow_mode: false }
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
      shadow_mode: true,
      foaf_url: Foaf::Config.api_url,
      foaf_reachable: version.present?,
      foaf_version: version,
      networks: networks&.size || 0,
      users_with_foaf_address: User.where.not(foaf_address: nil).count,
      users_total: User.count
    }
  end
end
