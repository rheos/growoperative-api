class Api::V1::DebugController < Api::V1::ApiController
  skip_before_action :authenticate!
  before_action :check_debug_enabled!

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
end
