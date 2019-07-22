module Api::V1
  class OrdersController < ApiController
    before_action :authenticate_user!

    def index
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
      params.require(:order_action).permit(:action_name, :request_id)
    end

    def order_params
      params.require(:order).permit(:order_label, :estimated_date)
    end
  end
end