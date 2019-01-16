module Api::V1
  class ItemsController < ApiController
    before_action :authenticate_user!, :check_user_type
    before_action :set_item, only: [:update, :destroy]

    # GET : /v1/items?range_degree=:integer 
    # This method will return all item which posted by contact of current user
    def index
      range_degree = params[:range_degree] ? [5, params[:range_degree].to_i].min : 5
      relationships = Relationship.where("user_id = #{current_user.id} OR friend_id = #{current_user.id}")
      @global_node_price = GlobalSetting.find_by(setting: "user_category_relationship_price") ? GlobalSetting.find_by(setting: "user_category_relationship_price").value : (ENV['user_category_relationship_price'] ? ENV['user_category_relationship_price'].to_f : 1)      
    
      if !current_user.is_producer? && relationships.count > 0 && range_degree > 0
        users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
        @items = Item.where("user_id IN (?)", users)
        step = (params[:range_degree] ? params[:range_degree].to_i : (GlobalSetting.find_by(setting: "RangeDegree") ? GlobalSetting.find_by(setting: "RangeDegree").value.to_i : (ENV['range_degree'] ? ENV['range_degree'] : 3)))
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
            route_price = helpers.get_relation_price(user, current_user.id)
           
            all_items(step - 1, user, current_user.id, user, route_price)
          end
        end
      else
        @items = current_user.items
        # # add items requested through user
        # if current_user.is_producer?
        #   request_items = ItemRequest.joins(:item)
        #     .where("friend_id = #{current_user.id}")
        #     .select("items.*, item_requests.price AS total_price")

        #   @items = (@items + request_items)
        # end
      end

      # @items = @items.as_json
      # @items = @items.sort_by{ |item| item.key?('total_price') ? item['total_price'] : item['price'] }.uniq{ |item| item['id']}
      @items = @items.sort_by{ |item| item.total_price }.uniq{ |item| item.id}

      # get pending requests
      pending_requests = {}
      ItemRequest.joins(:request_contract)
        .where("request_contracts.status = 0 AND item_requests.friend_id = #{current_user.id} AND item_requests.status = 0")
        .group("item_requests.item_id")
        .select("item_requests.item_id, COUNT(item_requests.id) AS action_request")
        .each do |request|
          pending_requests[request.item_id] = request.action_request
        end
      
      # assign count
      @items.collect do |item|
        item.action_request = pending_requests.key?(item['id']) ? pending_requests[item['id']] : 0
      end

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
          next_route_price += helpers.get_relation_price(user, related_user)

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
      # check if there is a user using this item
      # destory if there is only owner, else destory owner's inventory only
      if current_user.is_admin? || @item.inventory.where("user_id <> #{@item.user_id}").size == 0
        @item.destroy!
      else
        @item.inventory.where(user_id: @item.user_id).destroy_all
      end
      
      render json: {
        message: "Item delete successfully."
      }, staus: 200
    end

    # GET: /v1/items/around
    # Return around items
    def around
      depth_limit = 4
      max_items = 16
      queue_ids = [current_user.id]
      user_ids = [current_user.id]

      (1..depth_limit).each do |step|
        queue_ids = Relationship.where("user_id IN (#{user_ids.join(',')}) OR friend_id IN(#{user_ids.join(',')})")
          .pluck(:user_id, :friend_id)
          .flatten!.uniq
        
        # remove checked users
        queue_ids = queue_ids - user_ids

        # add users
        user_ids = user_ids + queue_ids
      end

      queue_ids.delete(current_user.id)

      # Recursive SQL is availbe on Mysql 8
      # sql = "
      #   WITH RECURSIVE get_friends(obj_user_id, depth, cycle) AS (
      #     SELECT IF(user_id = #{current_user.id}, friend_id, user_id), 1, false
      #     FROM relationships
      #     WHERE user_id = #{current_user.id} OR friend_id = #{current_user.id}
      #   UNION ALL
      #     SELECT IF(user_id = obj_user_id, friend_id, user_id), get_friends.depth + 1, user_id = ANY(obj_user_id)
      #     FROM relationships
      #     WHERE NOT cycle AND (depth < #{depth_limit}) AND (user_id = obj_user_id OR friend_id = obj_user_id)
      #   )
      #   SELECT DISTINCT(obj_user_id) FROM get_friends;"
      # user_ids = ActiveRecord::Base.connection.execute(sql).pluck('obj_user_id')
      items = Item.where("user_id IN(#{user_ids.join(',')})").limit(max_items)

      render json: items, status: 200
    end

    private
    def set_item
      @item = current_user.is_admin? ? Item.find(params[:id]) : current_user.items.find_by(id: params[:id])
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