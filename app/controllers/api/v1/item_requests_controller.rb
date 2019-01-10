module Api::V1
  class ItemsController < ApiController
    before_action :authenticate_user!
    before_action :set_item, only: [:update, :destroy]
   

    private
    def set_item
      @item = current_user.items.find_by(id: params[:id])
      unless @item
        render json: {
          message: "You are not authorised to access."
        }, status: 422
      end
    end

    def item_params
      params.require(:item).permit(:user_id,:quantity, :category_id,:item_name_id, :name, :grade_id, :price, :date_available, :item_unit_id, :unit, :created_at, :organic)
    end
  end
end