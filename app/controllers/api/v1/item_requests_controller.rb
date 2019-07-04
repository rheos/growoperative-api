module Api::V1
  class ItemRequestsController < ApiController
    before_action :authenticate_user!
    before_action :set_request, only: [:accept, :cancel, :settle, :sign]
   
    MAX_DEPTH = 5
    
    # URL: /v1/items/:inventory_id/requests
    def index
      requests = ItemRequest.with_inventory_data
        .select("
          item_requests.*, 
          request_contracts.status AS chain_status,
          request_contracts.quantity AS quantity,
          inventories.item_id,
          IF(request_contracts.status = 2 AND request_contracts.user_id = item_requests.user_id, 1, 0) AS need_sign
        ")
        .where("
          (item_requests.user_id=#{current_user.id} OR item_requests.friend_id=#{current_user.id}) AND
          request_contracts.inventory_id=#{params[:item_id]} AND 
          item_requests.status < 3
        ")
        .as_json
      res = {}
      requests.each do |r|
        if r['user_id'] == current_user.id
          r['contact_name'] = helpers.target_user_name(current_user.id, r['friend_id'])
          r['direction'] = 'sent'
        else
          r['contact_name'] = helpers.target_user_name(current_user.id, r['user_id'])
          r['direction'] = 'received'
        end

        if res[r['request_contract_id']].nil?
          res[r['request_contract_id']] = {}
        end
        res[r['request_contract_id']][r['id']] = r;
      end

      render json: res, status: 200
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
          unless inventory.producer_owns?
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
      request_contract.steps = shortest[:prices].size

      request_contract.save!

      # add source user id
      shortest[:path] << inventory.user_id
      shortest[:prices].reverse!
      # create requests
      current_prise = inventory.price
      shortest[:prices].each_with_index do |price, index|
        request = ItemRequest.new
        request.request_contract_id = request_contract.id
        request.user_id = shortest[:path][index]
        request.friend_id = shortest[:path][index + 1]
        request.price = inventory.price + price
        request.status = :pending
        request.sent = request.user_id == current_user.id ? 1 : 0
        request.step = shortest[:prices].size - index
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
      @request.accepted_at = DateTime.now
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
      inventory = Inventory.find(@request.request_contract.inventory_id)
      if inventory.nil? || !inventory.reserved?
        render json: { message: 'Not availabe to settle the inventory' }, status: 402
        return
      end

      # update current item request
      current_chain_item_request = ItemRequest.find_by(id: @request.id, step: request_contract.current_step + 1)
      unless current_chain_item_request
        logger.info "Previous request chain is not completed"
        render json: { message: 'Not availabe to settle the inventory' }, status: 406
        return
      end
      current_chain_item_request.shipped_at = DateTime.now
      current_chain_item_request.status = :completed
      current_chain_item_request.save!

      #TODO remove item from inventory here

      render json: { message: 'Request has been settled' }, status: 200
    end
    
    # POST: /v1/items/requests/:request_id/sign
    def sign
      unless @request.user_id == current_user.id
        render json: { message: 'The request was not reserved' }, status: 406
        return
      end

      unless (@request.request_contract.completed? || @request.request_contract.accepted?)
        render json: { message: 'Unable to sign it' }, status: 406
        return
      end

      # Update current contract step and finish contract, if all steps are done
      request_contract = @request.request_contract
  
      request_contract.current_step += 1
      if request_contract.current_step == request_contract.steps
        request_contract.status = :completed
      end

      request_contract.save!

      @request.update(signed_at: DateTime.now)

      # change inventory ownership
      inventory = Inventory.find_by(id: @request.request_contract.inventory_id)
      inventory.user_id = @request.user_id
      next_request = ItemRequest.find_by(request_contract_id: request_contract.id, friend_id: current_user.id)
      inventory.price = next_request ? next_request.price : @request.price
      inventory.save!

      render json: { message: 'Request has been signed' }, status: 200
    end

    # GET: /v1/items/requested
    def requested
      items = ItemRequest.joins(:request_contract)
        .where("item_requests.user_id = #{current_user.id} AND item_requests.sent = 1 AND request_contracts.status < 2 AND item_requests.status < 2")
      items = items.map do |item|
        json = item.to_json(current_user)
        json[:id] = json[:attributes]["inventory_id"]
        json
      end

      render json: {
        data: items
      }, status: 200
    end

    # GET: /v1/items/reserved
    def reserved
      items = Inventory.with_contract_data
        .select("inventories.*, request_contracts.inventory_id AS old_id, item_requests.price AS current_price")
        .where("
          (inventories.user_id = #{current_user.id} AND (inventories.status = 0 OR inventories.status = 2)) 
          OR 
          (request_contracts.status = 1 AND item_requests.user_id = #{current_user.id} AND item_requests.status = 2)
        ").uniq

      items = items.map do |item|
        json = item.to_json(current_user)
        unless item['old_id'].nil?
          json[:id] = item['old_id']
        end
        json
      end

      render json: {
        data: items
      }, status: 200
    end

    # GET: /v1/items/settled
    def settled
      items = ItemRequest.with_inventory_data
        .select("item_requests.*")
        .where("
          item_requests.friend_id = #{current_user.id} AND 
          item_requests.signed_at IS NOT NULL AND
          item_requests.status = 2
        ")
      items = items.uniq{ |item| item.request_contract_id}

      items = items.map do |item|
        json = item.to_json(current_user)
        json[:id] = item.inventory.id
        json[:attributes]['signed'] = item['signed']
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