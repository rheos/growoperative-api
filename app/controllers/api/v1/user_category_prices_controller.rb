module Api::V1
  class UserCategoryPricesController < ApiController
    # before_action :authenticate_user!

    # This action will create UserCategoryPrice
    # url       : /v1/user_category_prices
    # method    : POST
    # parameter : {"user_category_price": {
    #                  "price": 10.5,
    #                  "category_id": 1,
    #                  "unit": "ML"}
    #              }
    def create
      @user_category_price = current_user.user_category_prices.where(user_id: current_user.id).first_or_create(user_category_price_params)
      @user_category_price.price = user_category_price_params[:price]
      @user_category_price.price_type = user_category_price_params[:price_type] if user_category_price_params[:price_type].present?
      if @user_category_price.save
        render json: @user_category_price, status: 200
      else
        render :json=> @user_category_price.errors, :status=>422
      end
    end

    private
    def user_category_price_params
      params.require(:user_category_price).permit(:user_id,:category_id, :price, :price_type, :unit)
    end
  end
end
