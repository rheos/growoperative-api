module Api::V1
  class UserRelationshipPricesController < ApiController
    # before_action :authenticate_user!

    # This will return all item name
    # URl : v1/user_relationship_prices
    # Method : GET
    def index
      render json: UserRelationshipPrice.all
    end
    # This action will create UserRelationshipPrice
    # url       : /v1/user_relationship_prices
    # method    : POST
    # parameter : { "user_relationship_price": {
    #                   "price": 10.5,
    #                   "category_id": 1,
    #                   "friend_id": 2,
    #                   "relationship_id": 1}
    #             }

    def create
      if current_user.user_relationship_prices.find_by(friend_id: user_relationship_price_params[:friend_id])
        @user_relationship_price = current_user.user_relationship_prices.where("friend_id = #{user_relationship_price_params[:friend_id]}").update(user_relationship_price_params)
        render json: @user_relationship_price, status: 200
      else  
        @user_relationship_price = current_user.user_relationship_prices.new(user_relationship_price_params)
        if @user_relationship_price.save
          render json: @user_relationship_price, status: 200
        else
          render :json=> @user_relationship_price.errors, :status=>422
        end
      end
      
    end

    private
    def user_relationship_price_params
      params.require(:user_relationship_price).permit(:user_id,:friend_id, :category_id, :relationship_id, :price, :price_type, :receiving_price, :receiving_price_type)
    end
  end
end
