module Api::V1
  class ItemsController < ApiController
    before_action :authenticate_user!, :check_user_type
    before_action :set_inventory, only: [:update, :destroy]

    # GET : /v1/items?range_degree=:integer 
    # This method will return all item which posted by contacts of current user
    def index
      range_degree = (params[:range_degree] || ENV['range_degree'] || 0).to_i    
      relationships = Relationship.where("user_id=#{current_user.id} OR friend_id=#{current_user.id}")

      if !current_user.is_producer? && relationships.count > 0 && range_degree > 0
        users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
        @items = Inventory.where("inventories.user_id IN (?) AND inventories.quantity > 0 AND inventories.status = 1", users)
        @items.each do |item|
          item.target_user_id = item.user_id
          if item.producer_owns?
            item.total_price = item.price
          else
            item.total_price = item.price + helpers.get_relation_price(item.user_id, current_user.id)
          end
        end

        if range_degree > 1 
          users.delete(current_user.id)
          users.each do |user|    
            route_price = helpers.get_relation_price(user, current_user.id)
            all_items(range_degree - 1, user, current_user.id, user, route_price)
          end
        end
      else
        @items = current_user.inventories.where("status = 1 AND quantity > 0")
        
        # add items requested through user
        if current_user.is_producer?
          request_items = Inventory.with_contract_data
            .where("inventories.status = 1 AND inventories.quantity > 0 AND item_requests.user_id = #{current_user.id}")
            .select("inventories.*, item_requests.price AS total_price, item_requests.friend_id AS target_user_id")
            .each do |item|
              item.total_price = item[:total_price]
              item.target_user_id = item[:target_user_id]
            end

          @items = (@items + request_items)
        end

      end

      @items = @items.sort_by{ |item| item.total_price.to_f }.uniq{ |item| item.id}

      # get pending requests
      pending_requests = {}
      ItemRequest.with_inventory_data
        .where("item_requests.friend_id = #{current_user.id} AND item_requests.status = 0")
        .group("inventories.id")
        .select("inventories.id AS inventory_id, COUNT(item_requests.id) AS action_request")
        .each do |request|
          pending_requests[request.inventory_id] = request.action_request
        end
      
      # assign count
      result = @items.map do |item|
        item.action_request = pending_requests.key?(item.id) ? pending_requests[item.id] : 0
        item.to_json(current_user)
      end

      # add available count for waiting chain members
      # result.map do |item|
      #   requested_inventory = Inventory.with_inventory_data
      #   .where('
      #     inventories.status = 2
      #     AND 
      #   ')
      # end

      render json: {
        data: result
      }, status: 200
    end

    def all_items(step, related_user, before_user, target_user_id, route_price)
      relationships = Relationship.where("user_id = #{related_user} OR friend_id = #{related_user}")
      users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
      users.delete(before_user)
      users.delete(related_user)

      newitems = Inventory.where("user_id IN (?) AND quantity > 0 AND status = 1", users)
      newitems.each do |item|
        item.target_user_id = target_user_id
        item.total_price = item.price + route_price
        unless item.producer_owns?
          item.total_price += helpers.get_relation_price(item.user_id, related_user)
        end
      end

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
      data = item_params

      # add mark up price if item is producer's
      if params[:dtype].to_i != 1
        data[:producer_id] = current_user.id
      end

      @item = current_user.items.new(data)
      if @item.save
        render json: {
          data: @item.inventory[0].to_json(current_user)
        }, status: 200
      else
        render :json=> @item.errors, :status=>422
      end
    end

    def update
      data = item_params

      # add mark up price if item is producer's
      if params[:item][:dashboard_type] != 'broker'
        data[:producer_id] = current_user.id
      end

      if @inventory.update(price: data[:price], quantity: data[:quantity]) && @inventory.item.update(data)
        render json: {
          data: @inventory.to_json(current_user)
        }, status: 200
      else
        render :json=> @item.errors, :status=>422
      end
    end

    def destroy
      # check if there is a user using this item
      # destory if there is only owner, else destory owner's inventory only
      if current_user.is_admin? || Inventory.where("item_id = #{@inventory.item_id}").size == 1
        @inventory.item.destroy!
      else
        @inventory.destroy
      end
      
      render json: {
        message: "Item has been deleted successfully."
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
        queue_ids = Relationship.where("user_id IN (#{queue_ids.join(',')}) OR friend_id IN(#{queue_ids.join(',')})")
          .pluck(:user_id, :friend_id)
          .flatten!
        
        break if queue_ids.nil?

        queue_ids = queue_ids.uniq
        # remove checked users
        queue_ids = queue_ids - user_ids

        # add users
        user_ids = user_ids + queue_ids
      end

      user_ids.delete(current_user.id)

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
      if user_ids.size > 0
        items = Inventory.joins(:item).where("
          inventories.user_id = items.producer_id AND
          inventories.user_id IN(#{user_ids.join(',')}) AND 
          inventories.quantity > 0 AND 
          inventories.status = 1
        ").limit(max_items)
        items = items.map do |item|
          item.to_json(current_user)
        end
      else
        items = []
      end

      render json: {
        data: items
      }, status: 200
    end    

    # GET: /v1/items/reset
    def reset
      unless current_user.is_admin?
        render json: {
          message: "You are not authorised to access."
        }, status: 422
        return
      end

      ItemRequest.destroy_all
      RequestContract.destroy_all
      Inventory.destroy_all
      
      sql = "INSERT INTO inventories (item_id, user_id, quantity, price, status, created_at, updated_at)  
        SELECT id, user_id, quantity, price, 1, NOW(), NOW()
        FROM items"
      ActiveRecord::Base.connection.execute(sql)

      render json: {
        message: "Success"
      }, status: 200
    end

    private
    def set_inventory
      @inventory = current_user.is_admin? ? Inventory.find(params[:id]) : Inventory.find_by(id: params[:id], user_id: current_user.id)
      unless @inventory
        render json: {
          message: "You are not authorised to access."
        }, status: 422
      end
    end

    def item_params
      params.require(:item).permit(:user_id, :quantity, :category_id,:item_name_id, :name, :grade_id, :price, :date_available, :item_unit_id, :unit, :created_at, :organic)
    end

    def inventory_params
      params.require(:item).permit(:quantity, :price)
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