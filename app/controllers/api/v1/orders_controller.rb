module Api::V1
  class OrdersController < ApiController
    before_action :authenticate_user!

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

    def order_action_params
      params.require(:order_action).permit(:action_name, :item_id)
    end

    def order_params
      params.require(:order).permit(:order_label, :estimated_date, :user_id, :friend_id)
    end
  end
end