module Api::V1
  class ItemsController < ApiController
    before_action :authenticate_user!, :check_user_type
    before_action :set_item, only: [:update, :destroy]
    # This method will return all item which posted by contact of current user
    # url : /v1/items
    # method : GET
    def index
      relationships = Relationship.where("user_id = #{current_user.id} OR friend_id = #{current_user.id}")
      # @global_node_price = GlobalSetting.find_by(setting: "user_category_relationship_price").value
      @global_node_price = GlobalSetting.find_by(setting: "user_category_relationship_price") ? GlobalSetting.find_by(setting: "user_category_relationship_price").value : (ENV['user_category_relationship_price'] ? ENV['user_category_relationship_price'].to_f : 1)
      if relationships.count > 0
        users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
        @items = Item.where("user_id IN (?)", users)
        step = GlobalSetting.find_by(setting: "RangeDegree") ? GlobalSetting.find_by(setting: "RangeDegree").value.to_i : (ENV['range_degree'] ? ENV['range_degree'] : 3)
        # step = 3
        @items.each do |item|
          item.target_user_id = item.user_id
          item.total_price = item.price
          # temp producer if item.user.user_groups.pluck(:group_label).exclude?("producer")
          # route_price
            # if UserRelationshipPrice.where("user_id = #{current_user.id} AND friend_id = #{item.user_id}").first
            #   item.total_price += UserRelationshipPrice.where("user_id = #{current_user.id} AND friend_id = #{item.user_id}").first.price
            # else
            #   if item.category.default_node_price
            #     item.total_price += item.category.default_node_price
            #   else
            #     item.total_price += @global_node_price
            #   end
            # end
          # end
        end
        if step > 1 
          users.delete(current_user.id)
          users.each do |user|    
            route_price = 0
            # route_price
            if UserRelationshipPrice.where("user_id = #{user} AND friend_id = #{current_user.id}").first
              relPrice = UserRelationshipPrice.where("user_id = #{user} AND friend_id = #{current_user.id}").first.price
              if relPrice
                route_price += relPrice
              end
            else
              if User.find(user).user_category_prices.find_by(user_id: user)
                route_price += User.find(user).user_category_prices.find_by(user_id: user).price

              elsif Category.first.default_node_price
                route_price += Category.first.default_node_price
              else
                route_price += @global_node_price
              end
            end
            all_items(step - 1, user, current_user.id, user, route_price)
          end
        end
      else
        @items = current_user.items
      end
      @items = @items.sort_by{ |item| item.total_price }.uniq{ |item| item.id}
      render json: @items, status: 200
    end

    def all_items(step, related_user, before_user, target_user_id, route_price)
      relationships = Relationship.where("user_id = #{related_user} OR friend_id = #{related_user}")
      users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
      users.delete(before_user)
      users.delete(related_user)
      newitems = Item.where("user_id IN (?)", users)
      newitems.each do |item|
        item.target_user_id = target_user_id
        item.total_price = route_price + item.price
        #temp producer if item.user.user_groups.pluck(:group_label).exclude?("producer")
          # route_price
          # if UserRelationshipPrice.where("user_id = #{related_user} AND friend_id = #{item.user_id}").first
          #   # binding.pry
          #   item.total_price += UserRelationshipPrice.where("user_id = #{related_user} AND friend_id = #{item.user_id}").first.price
            
          # else
          #   if item.category.default_node_price
          #     item.total_price += item.category.default_node_price
          #   else
          #     item.total_price += @global_node_price
          #   end
          # end
        # end
      end
      # @items = (@items + newitems).uniq
      @items = (@items + newitems)
      # binding.pry
      if(step > 1)
        users.each do |user|
          next_route_price = route_price
          # route_price
          if UserRelationshipPrice.where("user_id = #{user} AND friend_id = #{related_user}").first
            relPrice = UserRelationshipPrice.where("user_id = #{user} AND friend_id = #{related_user}").first.price
            if relPrice
              next_route_price += relPrice
            end
          else
            if User.find(user).user_category_prices.find_by(user_id: user)
              next_route_price += User.find(user).user_category_prices.find_by(user_id: user).price
            elsif Category.first.default_node_price
              next_route_price += Category.first.default_node_price
            else
              next_route_price += @global_node_price
            end
          end

          # binding.pry
          all_items(step - 1, user, related_user, target_user_id, next_route_price)
        end
      end
      @items
    end
    #This method will create item
    #url /v1/items
    #method : POST
    #parameter
    def create
      @item = current_user.items.new(item_params)
      if @item.save
        render json: @item, status: 200
      else
        render :json=> @item.errors, :status=>422
      end
    end

    def update
      if @item.update(item_params)
        render json: @item, status: 200
      else
        render :json=> @item.errors, :status=>422
      end
    end

    def destroy
      @item.destroy!
      render json: {
        message: "Item delete successfully."
      }, staus: 200
    end

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

    def check_user_type
      # unless (current_user.user_groups.pluck(:group_label).include?("producer") || current_user.is_admin?)
      #   render json: {
      #     message: "You are not authorised to access."
      #   }, status: 422
      # end
    end
  end
end