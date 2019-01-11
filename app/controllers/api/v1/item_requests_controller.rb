module Api::V1
  class ItemRequestsController < ApiController
    before_action :authenticate_user!
   
    MAX_DEPTH = 5
    
    # URL: /v1/items/:item_id/requests
    def index
      requests = ItemRequest.where("item_id=#{params[:item_id]} AND user_id=#{current_user.id}")

      render json: requests, status: 200
    end

    # url: /v1/items/:item_id/requests
    # method : POST
    def create
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

            price = contact[:total] + helpers.get_relation_price(contact[:user_id], relation_id)
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
    def request_params
      params.require(:request).permit(:quantity)
    end

  end
end