module Api::V1
  class ItemsController < ApiController
    # before_action :authenticate_user!
    before_action :check_user_type
    before_action :set_inventory, only: [:update, :destroy]

    # GET : /v1/items?range_degree=:integer 
    # This method will return all item which posted by contacts of current user
    def index

      # 0 - ALL;   1 - ONLY SELL; 2 - ONLY BUY; 3 - NONE;
      range_degree = (params[:range_degree] || ENV['range_degree'] || 0).to_i
      
      # EXCLUDE CONSUMERS FROM HERE && REQUEST CHAIN
      relationships = Relationship.where("(user_id=#{current_user.id} AND friend_actions_state < 2 AND (actions_state = 0 || actions_state = 2)) OR (friend_id=#{current_user.id} AND actions_state < 2 AND (friend_actions_state = 0 || friend_actions_state = 2))")

      if (!current_user.is_producer? && relationships.count > 0 && range_degree > 0) || (params[:dashboard_type] == 'consumer')
        users = relationships.pluck(:user_id, :friend_id).flatten!.uniq
  
        # include only retailer relations if user is a consumer
        if params[:dashboard_type] != 'consumer'
          users = users.select {|id| !User.find(id).only_consumer_retailer?}
        else
          range_degree = 0
          users = users.select{|u| u != current_user.id && User.find(u).has_role?('retailer')}
        end

        if users.length > 0
          @items = Inventory.where("(inventories.user_id IN (?) AND inventories.quantity > 0 AND inventories.status = 1 AND inventories.user_id != #{current_user.id}) OR (inventories.user_id IN (?) AND inventories.status = 2 AND inventories.user_id != #{current_user.id} AND (
            (SELECT COUNT(id) FROM request_contracts WHERE request_contracts.inventory_id = inventories.id
            AND (request_contracts.status = 0 OR request_contracts.status = 3)
            AND request_contracts.id IN (SELECT request_contract_id FROM item_requests WHERE (item_requests.status = 1) AND item_requests.sent = 0 AND item_requests.user_id = #{current_user.id}) > 0)
          ))", users, users).uniq

          # if params[:dashboard_type] == 'consumer'
          #   @items = @items.select{ |item| item.generate_options.length > 0}
          # end

          @items.each do |item|
            item.target_user_id = item.user_id
            if item.apply_first_hop_markup?
              if item.status == "reserved" && item.item_requests.count
                adj_price = item.item_requests.where(user_id: current_user.id, status: "reserved").first&.price
              end
              markup = helpers.get_relation_price(item.user_id, current_user.id)
              item.total_price = adj_price || markup.apply_to(item.price || 0)
            else
              item.total_price = item.price
            end
          end
  
          if range_degree > 1 
            users.delete(current_user.id)
            users.each do |user|    
              route_markups = [helpers.get_relation_price(user, current_user.id)]
              all_items(range_degree - 1, user, current_user.id, user, route_markups)
            end
          end
        else
          @items = []
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
        requested_contracts = item.item_requests.where(user_id: current_user.id, status: [:pending, :reserved], sent: true).map(&:request_contract_id)
        requested_quantity = RequestContract.where(id: requested_contracts).sum(:quantity)
        item.quantity -= requested_quantity
        item if item.quantity > 0 || current_user.is_consumer?
      }.compact

      # get pending requests
      pending_requests = {}
      ItemRequest.with_inventory_data
        .where("((item_requests.friend_id = #{current_user.id} AND item_requests.status = 0))")
        .group("inventories.id")
        .select("inventories.id AS inventory_id, COUNT(item_requests.id) AS action_request, inventories.ref_id AS reserved_id")
        .each do |request|
          pending_requests[request.inventory_id] = request.action_request
          pending_requests[request.reserved_id] = request.action_request if request.reserved_id
        end
      
      # assign count
      result = @items.map do |item|
        item.action_request = pending_requests.key?(item.id) ? pending_requests[item.id] : 0
        item.to_json(current_user)
      end

      render json: { data: result }, status: 200
    end

    def all_items(step, related_user, before_user, target_user_id, route_markups)
      relationships = Relationship.where("user_id = #{related_user} OR friend_id = #{related_user}")
      users = relationships.pluck(:user_id, :friend_id).flatten!.uniq.select {|id| !User.find(id).only_consumer_retailer?}
      users.delete(before_user)
      users.delete(related_user)

      newitems = Inventory.where("user_id IN (?) AND quantity > 0 AND status = 1 AND user_id != #{current_user.id}", users)
      newitems.each do |item|
        item.target_user_id = target_user_id
        markups = item.apply_first_hop_markup? ? [helpers.get_relation_price(item.user_id, related_user)] + route_markups : route_markups
        item.total_price = helpers.apply_markup_chain(item.price, markups)
      end

      @items = (@items + newitems)

      if(step > 1)
        users.each do |user|
          next_route_markups = [helpers.get_relation_price(user, related_user)] + route_markups
          all_items(step - 1, user, related_user, target_user_id, next_route_markups)
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
      if params[:dtype].to_i == 1
        data[:producer_id] = current_user.id
      end
      description = data['description'] # Save description before removing it
      data_without_description = data.except('description')
      @item = current_user.items.new(data_without_description)
      if @item.save
        inventory = @item.inventory.first
        inventory.update(
          description: description,
          apply_first_hop_markup: apply_first_hop_markup_param
        )
        
        if params[:unit_options].present? && params[:unit_options].length > 0
          params[:unit_options].each do |option|
            size_params = JSON.parse(option)
            @item.inventory[0].unit_options.create(price: size_params["price"].to_f, quantity: size_params["quantity"].to_f, item_unit_id: size_params["item_unit_id"].to_i)
          end 
        end

        if(inventory_avatar_params[:inventory_avatars].present?)
          inventory.update_avatars(inventory_avatar_params, current_user.id)
          inventory.reload
        end

        render json: {
          data: inventory.reload.to_json(current_user)
        }, status: 200
      else
        render :json=> @item.errors, :status=>422
      end
    end

    # route 4 unit_options_destroy
    def unit_option_destroy
      inventory = Inventory.find_by(id: params[:item_id])
      return render json: {}, status: 404 if !inventory || (inventory.user_id != current_user.id && !current_user.is_admin?)

      unit_option = inventory.unit_options.find(params[:unit_id])
      return render json: {}, status: 404 unless unit_option

      unit_option.destroy

      return render json: {message: 'Unit option was destroyed!'}, status: 200

    end

    def update
      result = false
      if(params[:item].present?)
        data = item_params
        data_without_description = data.except('description')
        if (data[:description].present? || data[:description] == '') && !(item_params.keys.length > 1)
          result = @inventory.update(description: data[:description])
        elsif item_params.keys.length > 1
          change_item_name(@inventory, item_params[:name]) if item_params[:name].present?
          inventory_data = { price: data[:price], quantity: data[:quantity], description: data[:description] }
          inventory_data[:apply_first_hop_markup] = apply_first_hop_markup_param unless params[:apply_first_hop_markup].nil?
          result = @inventory.update(inventory_data) && @inventory.item.update(data_without_description)
        elsif item_params.keys.length == 1 && (data[:price] || data[:quantity])
          result = @inventory.update(data_without_description)
        else
          change_item_name(@inventory, item_params[:name]) if item_params[:name].present?
          result = @inventory.item.update(data_without_description)
        end

        if params[:unit_options].present?
          params[:unit_options].each do |option|
            size_params = JSON.parse(option)
            @inventory.unit_options.create(price: size_params["price"].to_f, quantity: size_params["quantity"].to_f, item_unit_id: size_params["item_unit_id"].to_i) unless size_params["id"]
          end
        end

        # Process images even when item attributes are also being updated
        if inventory_avatar_params[:inventory_avatars].present? || inventory_avatar_params[:source_images].present?
          @inventory.update_avatars(inventory_avatar_params, current_user.id)
          @inventory.reload
        end
      elsif(params[:inventory_avatars].present? || params[:source_images].present?)
        result = @inventory.update_avatars(inventory_avatar_params, current_user.id)
        @inventory.reload
      else
        result = @inventory.update_status(inventory_status_params)
      end

      if result
        render json: {
          data: @inventory.reload.to_json(current_user)
        }, status: 200
      else
        render :json=> @inventory.errors, :status=>422
      end
    end

    def destroy
      # check if there is a user using this item
      # destroy if there is only owner, else destroy owner's inventory only
      # binding.pry
      
      # First destroy any request contracts for this specific inventory
      RequestContract.where(inventory_id: @inventory.id).destroy_all
      
      # Check if this is the last inventory for the item AND user owns the item
      item = @inventory.item
      remaining_inventories = Inventory.where(item_id: item.id).where.not(id: @inventory.id)
      
      if (current_user.is_admin? || item.user_id == current_user.id) && remaining_inventories.count == 0
        # This is the last inventory and user owns the item, so delete the item too
        @inventory.destroy
        item.destroy!
      else
        # Just delete this inventory record
        @inventory.destroy
      end
      
      render json: {
        message: "Item has been deleted successfully."
      }, status: 200
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
      unless current_user.is_superuser?
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

    def change_item_name(inventory_for_update, name)
      item_name = ItemName.find_or_create_by(name: name, category_id: inventory_for_update.item.category_id)
      inventory_for_update.item.update(item_name_id: item_name.id, name: item_name.name)
      item_params.delete(:name)
    end

    def set_inventory
      @inventory = current_user.is_admin? ? Inventory.find(params[:id]) : Inventory.find_by(id: params[:id], user_id: current_user.id)
      unless @inventory
        render json: {
          message: "You are not authorised to access."
        }, status: 422
      end
    end

    def item_params
      @item_params ||= params.require(:item).permit(
        :user_id,
        :quantity,
        :category_id,
        :item_name_id,
        :name,
        :grade_id,
        :price,
        :date_available,
        :item_unit_id,
        :unit,
        :created_at,
        :organic,
        :description,
        :pack_contains_quantity,
        :pack_contains_unit_id,
        :condition,
        :one_time_listing
      )
    end

    def apply_first_hop_markup_param
      ActiveModel::Type::Boolean.new.cast(params[:apply_first_hop_markup])
    end

    def unit_option_params
      params.require(:unit_option).permit(:price, :quantity, :item_unit_id)
    end

    def unit_options_params
      params.premit(unit_options: [])
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
