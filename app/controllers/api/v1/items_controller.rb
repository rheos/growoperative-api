module Api::V1
  class ItemsController < ApiController
    before_action :authenticate_user!, :check_user_type
    before_action :set_item, only: [:update, :destroy]

    MAX_DEPTH = 5

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
            route_price = get_relation_price(user, current_user.id)
           
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
          next_route_price += get_relation_price(user, related_user)

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
      if @item.inventory.size > 1
        @item.inventory.where(user_id: @item.user_id).destroy_all
      else
        @item.destroy!
      end 
      
      render json: {
        message: "Item delete successfully."
      }, staus: 200
    end

    # url: /v1/items/:item_id/create_request
    # method : POST
    def create_request
      item = Item.find(params[:item_id])

      # check if item exists
      if item.nil?
        render json: { message: 'not available' }, status: 404
        return
      end
      
      # check if item is available
      contacts = [{ :user_id => item.user_id, :path => [], :prices => [], :total => 0 }]
      shortest = { :total => BigDecimal::INFINITY, :path => [], :prices => [] }
      checked_contacts = {}

      while contacts.size > 0 do
        contact = contacts.shift
        # mark as checked
        checked_contacts[contact[:user_id]] = contact[:total];

        # check if selected user is current user, it means item is available
        if contact[:user_id] == current_user.id 
          if contact[:total] < shortest[:total]
            shortest = contact
          end
        elsif contact[:path].size < MAX_DEPTH && 
          (relationships = Relationship.where("user_id = #{contact[:user_id]} OR friend_id = #{contact[:user_id]}")).size > 0
          # find from contacts
          relationships.pluck(:user_id, :friend_id).flatten!.uniq.each do |relation_id|
            next if relation_id == contact[:user_id]

            price = contact[:total] + get_relation_price(contact[:user_id], relation_id)
            if price < shortest[:total] && (checked_contacts[:relation_id].nil? || price < checked_contacts[:relation_id])
              contacts.push({
                :user_id => relation_id,
                :path => contact[:path] + [contact[:user_id]],
                :prices => contact[:prices] + [price],
                :total => price,
              })
            end
          end          
        end
      end

      # check if find a path
      if shortest[:total] == BigDecimal::INFINITY || shortest[:path].size == 0
        render json: { message: 'not available' }, staus: 400
        return
      end

      # add source user id
      shortest[:path] << current_user.id

      # create requests
      shortest[:prices].each_with_index do |price, index|
        request = ItemRequest.new
        request.item_id = item.id
        request.friend_id = shortest[:path][index]
        request.user_id = shortest[:path][index + 1]
        request.price = price
        request.quantity = request_params[:quantity]
        request.status = :pending
        request.save
      end

      render json: { message: 'Item has been requested successfully' }, staus: 200
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

    def request_params
      params.require(:request).permit(:quantity)
    end

    def check_user_type
      # unless (current_user.user_groups.pluck(:group_label).include?("producer") || current_user.is_admin?)
      #   render json: {
      #     message: "You are not authorised to access."
      #   }, status: 422
      # end
    end

    # get price of relationship between user and friend
    def get_relation_price(user_id, friend_id)
      # get relationship price first
      relation_price = UserRelationshipPrice.find_by(user_id: user_id, friend_id: friend_id)
      if (!relation_price.nil? && relation_price.price)
        return relation_price.price
      end

      # get default price
      category_price = UserCategoryPrice.find_by(user_id: user_id)
      if !category_price.nil?
        return category_price.price
      elsif Category.first.default_node_price
        return Category.first.default_node_price
      else
        return @global_node_price
      end
    end

  end
end