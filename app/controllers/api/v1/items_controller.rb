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
        @items = Inventory.where("(inventories.user_id IN (?) AND inventories.quantity > 0 AND inventories.status = 1 AND inventories.user_id != #{current_user.id}) OR (inventories.status = 2 AND inventories.user_id != #{current_user.id} AND (
          (SELECT COUNT(id) FROM request_contracts WHERE request_contracts.inventory_id = inventories.id 
          AND request_contracts.status = 0 
          AND request_contracts.id IN (SELECT request_contract_id FROM item_requests WHERE (item_requests.status = 4 OR item_requests.status = 1) AND item_requests.sent = 0 AND item_requests.user_id = #{current_user.id}) > 0)
        ))", users).uniq

        @items.each do |item|
          item.target_user_id = item.user_id
          if item.producer_owns?
            item.total_price = item.price
          else
            if item.status == "reserved" && item.item_requests.count
              adj_price = item.item_requests.where(user_id: current_user.id, status: "reserved").first&.price
            end
            item.total_price = adj_price || item.price + helpers.get_relation_price(item.user_id, current_user.id)
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
        @items = []
        
        # add items requested through user
        if current_user.is_producer?
          request_items = Inventory.with_contract_data
            .where("inventories.status = 1 AND inventories.quantity > 0 AND item_requests.user_id = #{current_user.id} AND inventories.user_id != #{current_user.id}")
            .select("inventories.*, item_requests.price AS total_price, item_requests.friend_id AS target_user_id")
            .each do |item|
              item.total_price = item[:total_price]
              item.target_user_id = item[:target_user_id]
            end

          @items = (@items + request_items)
        end

      end

      @items = @items.sort_by{ |item| item.total_price.to_f }.uniq{ |item| item.id}.map{ |item| 
        requested_contracts = item.item_requests.where(user_id: current_user.id, status: :pending).map(&:request_contract_id)
        requested_quantity = RequestContract.where(id: requested_contracts).sum(:quantity)
        item.quantity -= requested_quantity;
        item if item.quantity > 0
      }.compact

      # get pending requests
      pending_requests = {}
      ItemRequest.with_inventory_data
        .where("((item_requests.friend_id = #{current_user.id} AND item_requests.status = 0) OR (item_requests.user_id = #{current_user.id} AND item_requests.status = 4))")
        .group("inventories.id")
        .select("inventories.id AS inventory_id, COUNT(item_requests.id) AS action_request, inventories.ref_id AS reserved_id")
        .each do |request|
          pending_requests[request.inventory_id] = request.action_request
          pending_requests[request.reserved_id] = Inventory.find(request.reserved_id).item_requests.where("(item_requests.friend_id = #{current_user.id} AND item_requests.status = 0) OR (item_requests.user_id = #{current_user.id} AND item_requests.status = 4)").count if request.reserved_id
        end
      
      # assign count
      result = @items.map do |item|
        item.action_request = pending_requests.key?(item.id) ? pending_requests[item.id] : 0
        item.to_json(current_user)
      end

      render json: {
        data: result
      }, status: 200
    end

    def all_items(step, related_user, before_user, target_user_id, route_price)
      relationships = Relationship.where("user_id = #{related_user} OR friend_id = #{related_user}")
      users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
      users.delete(before_user)
      users.delete(related_user)

      newitems = Inventory.where("user_id IN (?) AND quantity > 0 AND status = 1 AND user_id != #{current_user.id}", users)
      newitems.each do |item|
        item.target_user_id = target_user_id
        item.total_price = item.price + route_price
        unless item.producer_owns?
          item.total_price += helpers.get_relation_price(item.user_id, related_user)
        end
      end

      @items = (@items + newitems)

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
      result = false
      if(params[:item].present?)
        data = item_params
        result = @inventory.update(price: data[:price], quantity: data[:quantity]) && @inventory.item.update(data)
      elsif(params[:inventory_avatars].present?)
        result = @inventory.update_avatars(inventory_avatar_params, current_user.id)
      else
        result = @inventory.update_status(inventory_status_params)
      end

      if result
        render json: {
          data: @inventory.to_json(current_user)
        }, status: 200
      else
        render :json=> @inventory.errors, :status=>422
      end
    end

    def destroy
      # check if there is a user using this item
      # destory if there is only owner, else destory owner's inventory only
      # binding.pry
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
      Order.destroy_all
      
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
      params.require(:item).permit(:user_id, :quantity, :category_id, :item_name_id, :name, :grade_id, :price, :date_available, :item_unit_id, :unit, :created_at, :organic)
    end

    def inventory_avatar_params
      params.permit({inventory_avatars: [], source_images: []})
    end
    
    def inventory_status_params
      params.require(:inventory).permit(:status)
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