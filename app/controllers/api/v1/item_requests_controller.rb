module Api::V1
  class ItemRequestsController < ApiController
    before_action :authenticate_user!
    before_action :set_request, only: [:accept, :cancel, :settle]
   
    MAX_DEPTH = 5
    
    # URL: /v1/items/:inventory_id/requests
    def index
      sent = ItemRequest.joins(:request_contract)
        .select("item_requests.*, request_contracts.status AS contract_status")
        .where("item_requests.inventory_id=#{params[:item_id]} AND item_requests.user_id=#{current_user.id} AND item_requests.status < 2")
        .as_json
      
      sent.each do |request|
        request[:contract_name] = helpers.target_user_name(current_user.id, request['friend_id'])
      end
      
      received = ItemRequest.joins(:request_contract)
        .select("item_requests.*, request_contracts.status AS contract_status")
        .where("item_requests.inventory_id=#{params[:item_id]} AND item_requests.friend_id=#{current_user.id} AND item_requests.status < 2")
        .as_json

      received.each do |request|
        request[:contract_name] = helpers.target_user_name(current_user.id, request['user_id'])
      end

      render json: {
        :sent => sent,
        :received => received,
      }, status: 200
    end

    # POST: /v1/items/:inventory_id/requests
    def create
      inventory = Inventory.find_by(id: params[:item_id])

      # check if inventory exists
      if inventory.nil? || inventory.status != 'available'
        render json: { message: 'inventory is not available' }, status: 404
        return
      end

      # check if inventory quanity is enough as much as requests
      if request_params[:quantity].nil? || inventory.quantity < request_params[:quantity].to_f
        render json: { message: 'not enough stock' }, status: 400
        return
      end

      if inventory.user_id == current_user.id
        render json: { message: 'can not request own item' }, status: 400
        return
      end
      
      # check if inventory is available
      contacts = [{ :user_id => current_user.id, :path => [], :prices => [], :total => 0, :route_price => 0 }]
      shortest = { :total => BigDecimal::INFINITY, :path => [], :prices => [] }
      checked_contacts = {}

      while contacts.size > 0 do
        contact = contacts.shift
        # mark as checked
        checked_contacts[contact[:user_id]] = contact[:total];

        # check if selected user is current user, it means inventory is available
        if contact[:user_id] == inventory.user_id
          # add user mark up if he is not owner
          if inventory.producer_id.nil?
            contact[:total] += helpers.get_relation_price(inventory.user_id, contact[:path].last)
          end

          if contact[:total] < shortest[:total]            
            shortest = contact
          end
        elsif contact[:path].size < MAX_DEPTH && 
          (relationships = Relationship.where("user_id = #{contact[:user_id]} OR friend_id = #{contact[:user_id]}")).size > 0
          # find from contacts
          relationships.pluck(:user_id, :friend_id).flatten!.uniq.each do |relation_id|
            next if relation_id == contact[:user_id]

            total = contact[:total] + contact[:route_price]
            if total < shortest[:total] && 
              (checked_contacts[:relation_id].nil? || total < checked_contacts[:relation_id])

              contacts.push({
                :user_id => relation_id,
                :path => contact[:path] + [contact[:user_id]],
                :prices => contact[:prices] + [total],
                :total => total,
                :route_price => helpers.get_relation_price(relation_id, contact[:user_id]),
              })
            end
          end
        end
      end

      # check if find a path
      if shortest[:total] == BigDecimal::INFINITY || shortest[:path].size == 0
        render json: { message: 'path not found' }, status: 400
        return
      end

      # create request contract
      request_contract = RequestContract.new
      request_contract.user_id = current_user.id
      request_contract.inventory_id = inventory.id
      request_contract.item_id = inventory.item_id
      request_contract.quantity = request_params[:quantity]
      request_contract.price = inventory.price + shortest[:total]
      request_contract.save!

      # add source user id
      shortest[:path] << inventory.user_id

      # create requests
      shortest[:prices].each_with_index do |price, index|
        request = ItemRequest.new
        request.request_contract_id = request_contract.id
        request.inventory_id = inventory.id
        request.user_id = shortest[:path][index]
        request.friend_id = shortest[:path][index + 1]
        request.price = request_contract.price - price
        request.quantity = request_params[:quantity]
        request.status = :pending
        request.save!
      end

      render json: { message: 'Item has been requested successfully' }, status: 200
    end

    # POST: /v1/items/requests/:request_id/accept
    # Return 200 response if success
    def accept
      # check permission
      unless current_user.is_admin? || @request.friend_id == current_user.id
        render json: { message: 'Not accessable' }, status: 403
        return
      end

      # check if request is pending
      unless @request.pending?
        render json: { message: 'Request is not pending' }, status: 406
        return
      end

      # check if the contract was accepted or cancelled already
      unless @request.request_contract.pending?
        render json: { message: 'The request chain is not available' }, status: 406
        return
      end

      @request.status = :accepted
      if @request.save!
        render json: { message: 'Request has been accepted' }, status: 200
      else
        render json: { message: 'Something is wrong' }, status: 500
      end
    end

    # POST: /v1/items/requests/:request_id/cancel
    # Return 200 response if success
    def cancel
      # check permission
      unless current_user.is_admin? || @request.friend_id == current_user.id || @request.user_id == current_user.id
        render json: { message: 'Not accessable' }, status: 403
        return
      end

      unless @request.request_contract.pending?
        render json: { message: 'Request chain is not pending already' }, status: 406
        return
      end

      if @request.friend_id == current_user.id
        unless @request.status == 'pending'
          render json: { message: 'Request is not pending' }, status: 406
          return
        end
  
        # cancel the user's request
        @request.status = :cancelled
        @request.save!
      end

      # cancel the request contract
      @request.request_contract.status = :cancelled
      @request.request_contract.save

      render json: { message: 'Request has been cancelled' }, status: 200
    end

    # POST: /v1/items/requests/:request_id/settle
    # Return 200 response if success
    def settle
      # check permission
      unless current_user.is_admin? || @request.friend_id == current_user.id || @request.inventory.user_id == current_user.id
        render json: { message: 'Not accessable' }, status: 403
        return
      end

      # check if all requests are accepted
      request_contract = @request.request_contract
      unless request_contract.reserved?
        render json: { message: 'The request chain was not accepted' }, status: 406
        return
      end

      # find the inventory
      inventory = Inventory.find_by(ref_id: @request.request_contract_id)
      if inventory.nil? || inventory.status != 'reserved'
        render json: { message: 'Not availabe to settle the inventory' }, status: 406
        return
      end

      # change inventory ownership
      inventory.user_id = request_contract.user_id
      inventory.price = request_contract.price
      inventory.status = :available
      inventory.save!

      # update contract
      request_contract.status = :settled
      request_contract.save!

      render json: { message: 'Request has been settled' }, status: 200
    end

    private
    def request_params
      params.require(:request).permit(:quantity, :price)
    end

    def set_request
      @request = ItemRequest.find_by(id: params[:id])
      if @request.nil?
        render json: {
          message: "The request does not exist"
        }, status: 404
      end
    end

  end
end