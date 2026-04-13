module Api::V1
  class OrdersController < ApiController
    # before_action :authenticate_user!

    def index
      orders = Order.includes(:item_requests)
        .where(user_id: current_user.id.to_s)
        .or(Order.includes(:item_requests).where(friend_id: current_user.id.to_s))
        .order(created_at: :desc)

      if params[:status].present?
        statuses = params[:status].split(',').map(&:strip)
        orders = orders.where(order_status: statuses)
      end

      render json: { data: orders.map { |o| serialize_order_summary(o) } }, status: 200
    end

    def show
      order = Order.includes(item_requests: { request_contract: { inventory: { item: :item_unit } } }).find_by(id: params[:id])
      render :json=> {error: 'Unable to find order'}, :status=>422 if !order
      return if !order

      unless current_user.id.to_s == order.user_id.to_s || current_user.id.to_s == order.friend_id.to_s || current_user.admin?
        render :json=> {error: 'Unauthorized'}, :status=>403
        return
      end

      render json: { data: serialize_order_detail(order) }, status: 200
    end

    def create
      # binding.pry
      if params[:order].present? && params[:order][:acceptable_item].present?
        request = ItemRequest.joins(:request_contract).where("request_contracts.inventory_id = #{params[:order][:acceptable_item]} AND friend_id = #{current_user.id} AND signed_at IS NULL AND shipped_at IS NULL")
        orders = Order.where(user_id: request.first.user_id.to_s, friend_id: request.first.friend_id.to_s, order_status: :pending) if request && request.first

        render json: { orders: orders || [] }, status: 200
      else
        item = Inventory.find(order_params[:user_id])
        request = ItemRequest.joins(:request_contract).where("item_requests.status = 1 AND request_contracts.inventory_id = #{item.id} && item_requests.friend_id = #{order_params[:friend_id]}")

        if request.first.nil?
          render :json=> {error: 'Unable to create order! This requests are finished'}, :status=>422
          return
        end

        args = order_params
        args[:user_id] = request.first.user_id
        args[:order_status] = 0
        order = Order.create(args)
        order.update(order_label: 'Order ' + order.id.to_s) if !order.order_label || order.order_label == ''
        if order
          render json: { order: order }, status: 200
        else
          render :json=> {error: 'Unable to create order!'}, :status=>422
        end
      end
    end

    def update
      order = Order.find_by(id: params[:id])
      render :json=> {error: 'Unable to find order'}, :status=>422 if !order
 
      if params[:order].present?
        if order.update(order_params)
          render json: { data: order }, status: 200
        else
          render :json=> {error: 'Unable to process order!'}, :status=>422
        end
        return
      end

      if order.apply_action(order_action_params, current_user.id)
        render json: {
          data: order
        }, status: 200
      else
        render :json=> {error: 'Unable to process order!'}, :status=>422
      end
    end

    def destroy
      order = Order.find_by(id: params[:id])
      render :json=> {error: 'Unable to find order'}, :status=>422 if !order
      if order.order_status == 'signed' && order.destroy!
        render json: {}, status: 200
      else
        render json: { error: 'Unable to destroy order!' }, status: 500
      end
    end

    def order_action_params
      params.require(:order_action).permit(:action_name, :item_id, :settlement_type, :cash_amount)
    end

    def order_params
      params.require(:order).permit(:order_label, :estimated_date, :estimated_time, :location, :note, :user_id, :friend_id)
    end

    def serialize_order_detail(order)
      buyer = User.find_by(id: order.user_id)
      seller = User.find_by(id: order.friend_id)

      {
        id: order.id,
        order_label: order.order_label,
        user_id: order.user_id,
        friend_id: order.friend_id,
        buyer_name: buyer&.user_name || 'Unknown',
        seller_name: seller&.user_name || 'Unknown',
        order_status: order.order_status,
        settlement_type: order.settlement_type,
        settlement_status: order.settlement_status,
        settlement_amount: serialized_settlement_amount(order),
        item_request_count: order.item_requests.count,
        shipped_on: order.shipped_on,
        signed_on: order.signed_on,
        created_at: order.created_at,
        updated_at: order.updated_at,
        items: order.item_requests.map do |request|
          contract = request.request_contract
          inventory = contract&.inventory
          item = inventory&.item
          {
            request_id: request.id,
            inventory_id: inventory&.id,
            name: item&.name || 'Item',
            quantity: contract&.quantity.to_f,
            unit_name: item&.item_unit&.item_symbol || '',
            price: request.price.to_f,
            status: request.status,
            buyer_name: User.find_by(id: request.user_id)&.user_name || 'Unknown',
            seller_name: User.find_by(id: request.friend_id)&.user_name || 'Unknown',
            accepted_at: request.accepted_at,
            shipped_at: request.shipped_at,
            signed_at: request.signed_at,
          }
        end
      }
    end

    def serialize_order_summary(order)
      buyer = User.find_by(id: order.user_id)
      seller = User.find_by(id: order.friend_id)

      {
        id: order.id,
        order_label: order.order_label,
        user_id: order.user_id,
        friend_id: order.friend_id,
        buyer_name: buyer&.user_name || 'Unknown',
        seller_name: seller&.user_name || 'Unknown',
        order_status: order.order_status,
        settlement_type: order.settlement_type,
        settlement_status: order.settlement_status,
        settlement_amount: serialized_settlement_amount(order),
        item_request_count: order.item_requests.size,
        shipped_on: order.shipped_on,
        signed_on: order.signed_on,
        created_at: order.created_at,
        updated_at: order.updated_at,
      }
    end

    def serialized_settlement_amount(order)
      settled_transaction = TrustlineTransaction.where(order_id: order.id)
        .where.not(transaction_type: 'reversal')
        .order(created_at: :desc)
        .first
      return settled_transaction.amount.to_f if settled_transaction

      order.item_requests
        .joins(:request_contract)
        .sum('item_requests.price * request_contracts.quantity')
        .to_f
    end
  end
end
