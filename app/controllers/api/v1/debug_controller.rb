class Api::V1::DebugController < Api::V1::ApiController
  skip_before_action :authenticate!

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
