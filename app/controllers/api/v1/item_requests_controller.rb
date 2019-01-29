module Api::V1
  class ItemRequestsController < ApiController
    before_action :authenticate_user!
    before_action :set_request, only: [:accept, :cancel, :settle, :sign]
   
    MAX_DEPTH = 5
    
    # URL: /v1/items/:inventory_id/requests
    def index
      sent = ItemRequest.joins(:request_contract)
        .select("item_requests.*, request_contracts.status AS chain_status, 
          IF(request_contracts.status = 2 AND request_contracts.signed = 0 AND request_contracts.user_id = item_requests.user_id, 1, 0) AS need_sign")
        .where("item_requests.inventory_id=#{params[:item_id]} AND item_requests.user_id=#{current_user.id} AND item_requests.status < 3")
        .as_json
      
      sent.each do |request|
        request[:contract_name] = helpers.target_user_name(current_user.id, request['friend_id'])
      end
      
      received = ItemRequest.joins(:request_contract)
        .select("item_requests.*, request_contracts.status AS chain_status")
        .where("item_requests.inventory_id=#{params[:item_id]} AND item_requests.friend_id=#{current_user.id} AND item_requests.status < 3")
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

      if @request.request_contract.completed? || @request.request_contract.cancelled?
        render json: { message: 'Request chain is not pending already' }, status: 406
        return
      end

      if @request.request_contract.accepted? && @request.request_contract.user_id == current_user.id
        render json: { message: 'Request is reserved already, you can not cancel' }, status: 406
        return
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
      unless request_contract.accepted?
        render json: { message: 'The request was not reserved' }, status: 406
        return
      end

      # find the inventory
      inventory = Inventory.find_by(ref_id: @request.request_contract_id)
      if inventory.nil? || !inventory.reserved?
        render json: { message: 'Not availabe to settle the inventory' }, status: 406
        return
      end

      # update contract
      request_contract.status = :completed
      request_contract.save!

      render json: { message: 'Request has been settled' }, status: 200
    end
    
    # POST: /v1/items/requests/:request_id/sign
    def sign
      unless @request.request_contract.user_id == current_user.id
        render json: { message: 'The request was not reserved' }, status: 406
        return
      end

      unless @request.request_contract.completed? && @request.request_contract.signed == 0
        render json: { message: 'Unable to sign it' }, status: 406
        return
      end

      @request.request_contract.signed = 1
      @request.request_contract.save!

      # change inventory ownership
      inventory = Inventory.find_by(ref_id: @request.request_contract_id)
      inventory.user_id = @request.user_id
      inventory.price = @request.request_contract.price
      inventory.save!

      render json: { message: 'Request has been signed' }, status: 200
    end

    # GET: /v1/items/requested
    def requested
      items = ItemRequest.joins("JOIN request_contracts ON request_contracts.id = item_requests.request_contract_id 
          LEFT JOIN item_requests AS t2 ON t2.request_contract_id = item_requests.request_contract_id AND t2.friend_id=#{current_user.id}")
        .select("item_requests.*, request_contracts.status AS chain_status, request_contracts.user_id AS receiver, signed")
        .where("(request_contracts.status < 2 OR (request_contracts.status = 2 AND signed = 0)) AND item_requests.user_id = #{current_user.id} 
          AND (request_contracts.user_id = #{current_user.id} OR t2.status = 1)")
      items = items.map do |item|
        json = item.to_json(current_user)
        json[:id] = item.inventory_id
        json[:attributes]['action-request'] = item['receiver'] == current_user.id && item['chain_status'] == 2 && item['signed'] == 0
        json
      end

      render json: {
        data: items
      }, status: 200
    end

    # GET: /v1/items/reserved
    def reserved
      items = Inventory.where("user_id = #{current_user.id} AND (status = 0 or status = 2)")

      items = items.map do |item|
        json = item.to_json(current_user)
        json
      end

      render json: {
        data: items
      }, status: 200
    end

    # GET: /v1/items/settled
    def settled
      items = ItemRequest.where("(user_id = #{current_user.id} OR friend_id = #{current_user.id}) AND status = 2")
      items = items.uniq{ |item| item.request_contract_id}

      items = items.map do |item|
        json = item.to_json(current_user)
        json
      end

      render json: {
        data: items
      }, status: 200
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