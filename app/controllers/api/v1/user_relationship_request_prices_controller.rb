module Api::V1
  class UserRelationshipRequestPricesController < ApiController
    before_action :authenticate_user!

    # This action will create UserCategoryPrice
    # url       : /v1/user_relationship_request_prices
    # method    : POST
    # parameter : {"user_relationship_request_price": {
    #                  "price": 10.5,
    #                  "category_id": 1,
    #                  "friend_id": 2,
    #                  "relationship_id": 1
    #                  "item_request_id": 1 } }
    def create
      @user_relationship_request_price = current_user.user_relationship_request_prices.new(user_relationship_request_price_params)
      if @user_relationship_request_price.save
        render json: @user_relationship_request_price, status: 200
      else
        render :json=> @user_relationship_request_price.errors, :status=>422
      end
    end

    private
    def user_relationship_request_price_params
      params.require(:user_relationship_request_price).permit(:user_id,:friend_id, :relationship_id, :price, :item_request_id)
    end
  end
end