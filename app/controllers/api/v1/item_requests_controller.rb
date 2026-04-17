module Api::V1
  class ItemRequestsController < ApiController
    before_action :set_request, only: [:accept, :cancel, :ship, :sign]
   
    MAX_DEPTH = 5
    
    # URL: /v1/items/:inventory_id/requests
    def index
      # Resolve the original inventory ID — if this is a reserved copy, follow ref_id
      # back to the original so we find all sibling copies too.
      inv = Inventory.find_by(id: params[:item_id])
      original_id = (inv&.ref_id.present? && inv.ref_id.to_i > 0) ? inv.ref_id : params[:item_id]

      requests = ItemRequest.with_inventory_data
        .select("
          item_requests.*,
          request_contracts.status AS chain_status,
          request_contracts.quantity AS quantity,
          request_contracts.unit AS unit,
          inventories.item_id,
          inventories.user_id AS inventory_owner_id,
          IF(request_contracts.user_id = item_requests.user_id, 1, 0) AS need_sign
        ")
        .where("
          (item_requests.user_id=#{current_user.id} OR item_requests.friend_id=#{current_user.id}) AND
          (request_contracts.inventory_id=#{original_id} OR inventories.ref_id=#{original_id} OR request_contracts.inventory_id=#{params[:item_id]}) AND
          (item_requests.status < #{params[:include_completed] == "true" ? 3 : 2} OR item_requests.status = 4)
        ")
        .uniq
      res = {}

      requests.each do |r|
        contract_chain_status = r.calculate_cahin_status
        r = r.as_json
        r['contract_chain_status'] = contract_chain_status
        if r['user_id'] == current_user.id
          r['contact_name'] = helpers.target_user_name(current_user.id, r['friend_id'])
          r['direction'] = 'sent'
        else
          r['contact_name'] = helpers.target_user_name(current_user.id, r['user_id'])
          r['direction'] = 'received'
        end
        r['unit'] = ItemUnit.find(r['unit'].to_i) if r['unit']
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
        render json: { message: 'Inventory is not available' }, status: 404
        return
      end

      # check if inventory quanity is enough as much as requests
      if request_params[:quantity].nil? || (inventory.quantity < request_params[:quantity].to_f && request_params[:unit].nil?)
        render json: { message: 'Not enough stock' }, status: 400
        return
      end

      if inventory.user_id == current_user.id
        render json: { message: 'Can not request own item' }, status: 400
        return
      end
  
      request_unit = nil
      contacts = [{ :user_id => current_user.id, :path => [], :prices => [], :total => 0, :route_price => 0 }]
      shortest = { :total => BigDecimal::INFINITY, :path => [], :prices => [] }
      checked_contacts = {}

      # default request chain calculation 
      if request_params[:unit].nil?
        # check if inventory is available
        contacts = [{ :user_id => current_user.id, :path => [], :prices => [], :total => 0, :route_price => 0 }]
        shortest = { :total => BigDecimal::INFINITY, :path => [], :prices => [] }
        checked_contacts = {}

        while contacts.size > 0 do
          contact = contacts.shift
          # mark as checked
          checked_contacts[contact[:user_id]] = contact[:total]

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
            relationships.pluck(:user_id, :friend_id).flatten!.uniq.select {|id| !User.find(id).only_consumer_retailer?}.each do |relation_id|
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
          render json: { message: 'Path not found' }, status: 400
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
        # create requests
        final_price = inventory.price + shortest[:total]
        shortest[:prices].each_with_index do |price, index|
          request = ItemRequest.new
          request.request_contract_id = request_contract.id
          request.user_id = shortest[:path][index]
          request.friend_id = shortest[:path][index + 1]
          request.price = final_price - price
          request.status = :pending
          request.sent = request.user_id == current_user.id ? 1 : 0
          request.step = shortest[:prices].size - index
          request.save!
        end
      else
        # request chain calculation for consumer -> retailer
        item_quantity = inventory.quantity * inventory.item.item_unit.equivalent
        unit = inventory.unit_options.find_by(id: request_params[:unit].to_i) || inventory.user.category_sizes.find_by(id: request_params[:unit].to_i)
        quantity = request_params[:quantity].to_f / unit.item_unit.equivalent

        return render json: { message: 'Not enough stock' }, status: 400 if (quantity >= item_quantity)

        # create request contract
        request_contract = RequestContract.new
        request_contract.user_id = current_user.id
        request_contract.inventory_id = inventory.id
        request_contract.item_id = inventory.item_id
        request_contract.quantity = request_params[:quantity].to_f
        request_contract.steps = 1
        request_contract.unit = unit.item_unit.id
        request_contract.save!

        request = ItemRequest.new
        request.request_contract_id = request_contract.id
        request.user_id = current_user.id
        request.friend_id = inventory.user.id
        request.price = unit.price
        request.status = :pending
        request.sent = request.user_id == current_user.id ? 1 : 0
        request.step = 1
        request.save!
      end

      notify_request_chain!(request_contract)

      render json: {
        message: 'Item has been requested successfully',
        data: {
          contract_id: request_contract.id,
          inventory_id: request_contract.inventory_id,
          requests: request_contract.item_requests.reload.map { |r| serialize_request_result(r) }
        }
      }, status: 200
    end

    # POST: /v1/items/requests/:request_id/accept
    # Return 200 response if success
    def accept
      # check permission
      unless current_user.is_admin? || @request.friend_id == current_user.id || (@request.status == "reserved" && @request.user_id == current_user.id)
        render json: { message: 'Not accessable' }, status: 403
        return
      end

      # check if request is pending
      unless (@request.pending? || @request.status == "reserved")
        render json: { message: 'Request is not pending' }, status: 406
        return
      end

      # check if the contract was accepted or cancelled already
      unless @request.request_contract.pending?
        render json: { message: 'The request chain is not available' }, status: 406
        return
      end

      # @request.status = :accepted
      # @request.accepted_at = DateTime.now
      result = @request.accept_request
      if result == true
        render json: { message: 'Request has been accepted', data: serialize_request_result(@request) }, status: 200
      elsif result[:message]
        render json: result.merge(data: serialize_request_result(@request)), status: 207
      else
        render json: { message: 'Something is wrong' }, status: 500
      end
    end
    # POST: /v1/items/requests/accept
    # Return 200 response if success
    def bulk_accept
      successful = true
      params[:ids].each do |id|
        item = Inventory.find_by(id: id)
        unless item
          successful = false
          next
        end

        requests = item.item_requests.where(status: :reserved, user_id: current_user.id).or(item.item_requests.where(status: :pending, friend_id: current_user.id))
        requests.each do |req|
          result = req.accept_request
          successful = result if result == false
        end
      end

      if successful == true
        render json: { message: 'Requests has been accepted', data: { accepted: true } }, status: 200
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

      # Save cancellation reason if provided
      @request.update(cancellation_reason: params[:reason]) if params[:reason].present?

      if @request.request_contract.completed? || @request.request_contract.cancelled?
        render json: { message: 'Request chain is not pending already' }, status: 406
        return
      end

      if @request.request_contract.accepted? && @request.request_contract.user_id == current_user.id
        render json: { message: 'Request is reserved already, you can not cancel' }, status: 406
        return
      end

      if @request.status == 'reserved'
        inventory = @request.request_contract.inventory
        Rails.logger.info "Cancel reserved request - Inventory ID: #{inventory.id}, Status: #{inventory.status}, Ref ID: #{inventory.ref_id}"
        
        # Mark contract as cancelled first so update_status will work properly
        @request.request_contract.update(status: :cancelled)
        
        # Use update_status to trigger quantity merge back to original inventory
        result = inventory.update_status(status: 'available')
        Rails.logger.info "Update status result: #{result}"
        
        order = Order.find_by(id: @request.order_id)
        order.destroy if order && ItemRequest.where(order_id: order.id).count == 1
        
        # Only destroy contract if inventory wasn't already destroyed by update_status
        @request.request_contract.destroy if RequestContract.exists?(@request.request_contract.id)

        render json: { message: 'Request has been cancelled', data: { id: @request.id, status: 'cancelled', inventory_id: inventory.id } }, status: 200
        return
      end

      # cancel the request contract
      order = Order.find_by(id: @request.order_id)
      @request.update(order_id: nil)
      order.destroy if order && ItemRequest.where(order_id: order.id).count == 0
      @request.request_contract.status = :cancelled
      @request.request_contract.save
      request_contract = @request.request_contract
      # Use update_status to trigger quantity merge if inventory was reserved
      request_contract.inventory.update_status(status: 'available') if (request_contract.inventory.status == 'reserved')

      render json: { message: 'Request has been cancelled', data: { id: @request.id, status: 'cancelled', inventory_id: request_contract.inventory_id } }, status: 200
    end

    # POST: /v1/items/requests/:request_id/ship
    # Return 200 response if success
    def ship
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
      inventory = @request.request_contract.inventory
      if inventory.nil? || !inventory.reserved?
        render json: { message: 'Not availabe to ship the inventory' }, status: 402
        return
      end

      # update current item request
      current_chain_item_request = ItemRequest.find_by(id: @request.id, step: request_contract.current_step + 1)
      unless current_chain_item_request
        logger.info "Previous request chain is not completed"
        render json: { message: 'Not availabe to ship the inventory' }, status: 406
        return
      end
      current_chain_item_request.ship

      render json: { message: 'Items has been shipped', data: serialize_request_result(current_chain_item_request) }, status: 200
    end
    
    # POST: /v1/items/requests/:request_id/sign
    def sign
      unless @request.user_id == current_user.id
        render json: { message: 'You can not sign this request' }, status: 406
        return
      end

      unless (@request.request_contract.completed? || @request.request_contract.accepted?)
        render json: { message: 'Unable to sign it' }, status: 406
        return
      end

      @request.sign
      render json: { message: 'Request has been signed', data: serialize_request_result(@request) }, status: 200
    end

    # POST: /v1/items/requests/reserve
    def reserve
      inventory = Inventory.find(reserve_params[:inventory_id])
      user = User.find(reserve_params[:user_id])

      if !inventory || !user || reserve_params[:quantity].to_f > inventory.quantity
        return render json: { message: 'Unable to reserve an item!' }, status: 404
      end
      price = helpers.get_relation_price(current_user.id, user.id) + inventory.price

      reserved = Inventory.new do |m|
        m.item_id = inventory.item_id
        m.user_id = inventory.user_id
        m.price = reserve_params[:price] || price
        m.quantity = reserve_params[:quantity]
        m.ref_id = inventory.id #ref_id is pointing to previous inventory, which is needs do be restored
        m.status = :reserved
        m.gallery_map = inventory.gallery_map
        m.ref_price = inventory.price
        m.save!
      end
      inventory.update(quantity: inventory.quantity - reserved.quantity)

      request_contract = RequestContract.new
      request_contract.user_id = user.id
      request_contract.inventory_id = reserved.id
      request_contract.item_id = reserved.item_id
      request_contract.quantity = reserved.quantity
      request_contract.steps = 1
      request_contract.save!

      request = ItemRequest.new
      request.request_contract_id = request_contract.id
      request.user_id = user.id
      request.friend_id = current_user.id
      request.price = reserve_params[:price] || price
      request.status = :reserved
      request.sent = request.user_id == current_user.id ? 1 : 0
      request.step = 1
      request.save!

      # Find or create order for this user relationship (same logic as accept_request)
      order = Order.find_or_create_pending(user.id, current_user.id)
      request.update(order_id: order.id)

      render json: { message: 'Item has been reserved', data: serialize_request_result(request) }, status: 200
    end

    # GET: /v1/items/requested
    def requested
      items = ItemRequest.with_inventory_data
        .where("
          ((item_requests.user_id = #{current_user.id} AND item_requests.signed_at IS NULL AND item_requests.sent = true
          AND request_contracts.status < 2) OR (item_requests.user_id = #{current_user.id} AND item_requests.status = 4))
          AND inventories.user_id <> #{current_user.id}
        ").uniq
      items = items.map do |item|
        json = item.to_json(current_user)
        json[:id] = json[:attributes]["inventory_id"]
        next_request = item.request_contract.item_requests.find_by(friend_id: current_user.id)
        json[:attributes]["need_sign"] = (item.shipped_at && !item.signed_at) || (next_request && next_request.status == "pending" ) || (item.status == 'reserved')
        json[:attributes]["action-request"] = item.inventory.item_requests.where(friend_id: current_user.id, status: :pending).exists?
        json
      end

      result = []
      items_without_order = []

      items = items.group_by{|i| i[:attributes]["order"]}.compact
      items.each do |key, value|
        # add inventory without an order, of there is no order
        if key.nil?
          items_without_order += value
        else
          order = Order.find(key)
          # add inventory without an order, of there are still unconfirmed requests, or previous chain member still waiting for delivery
          current_user_requests = order.item_requests.joins(:inventory).where("item_requests.user_id = #{current_user.id} AND inventories.user_id != item_requests.friend_id")
          request_ids = []
          if current_user_requests.count > 0 || order.request_contracts.where.not(status: :accepted).count > 0
            values_without_order = []
            current_user_requests.each do |request|
              request_ids << request.inventory.id
            end
            value.each do |request|
              values_without_order << request if request_ids.include?(request[:id])
            end
            value.delete_if { |request| request_ids.include?(request[:id]) }
            items_without_order += values_without_order
            # If extraction emptied the order group, skip the wrapper entirely —
            # otherwise the client renders a "0 items" placeholder card for an
            # order whose items now live in items_without_order.
            if value.any?
              res = order.as_json
              (current_user.id.to_s.in?([res['friend_id'], res['user_id']]) || res['shipped_on']) ? result.push({order: res, items: value}) : result.push(value)
            end
          else
            res = order.as_json
            (current_user.id.to_s.in?([res['friend_id'], res['user_id']]) || res['shipped_on']) ? result.push({order: res, items: value}) : result.push(value)
          end
        end
      end

      result.push(items_without_order) if items_without_order.length > 0
      render json: {
        data: result.compact
      }, status: 200
    end

    # GET: /v1/items/my_items
    def my_items
      result = Inventory.where("user_id = #{current_user.id} AND (status IN (0,1)) AND quantity > 0 
      AND (SELECT COUNT(id) FROM request_contracts WHERE request_contracts.inventory_id = inventories.id AND request_contracts.status NOT IN(0, 2, 3) AND request_contracts.archived = false) = 0")
      .map { |item| item.to_json(current_user) }.compact

      render json: {
        data: result
      }, status: 200
    end

    # GET: /v1/items/reserved
    def reserved
      requests = ItemRequest.with_inventory_data
        .select("item_requests.*, inventories.id AS inventory_id")
        .where("
          inventories.user_id = #{current_user.id}
          AND inventories.status = 2
          AND ((item_requests.friend_id = #{current_user.id} AND item_requests.shipped_at IS NULL)
          OR (item_requests.user_id = #{current_user.id} AND item_requests.signed_at IS NOT NULL AND (
            SELECT COUNT(*) FROM item_requests
            WHERE item_requests.request_contract_id = request_contracts.id AND item_requests.friend_id = #{current_user.id}
          ) = 0
          ))
          OR (item_requests.friend_id = #{current_user.id} AND item_requests.signed_at IS NULL AND item_requests.shipped_at IS NOT NULL AND request_contracts.status = 3)
        ")
      result = []
      requests = requests.map{|r| r.to_json(current_user)}.group_by{|i| i[:attributes]["order"]}

      requests.each do |key, value|
        inventory_ids = value.map{|i| i[:attributes]['inventory_id']}
        items = Inventory.where(id: inventory_ids).map{|item|
          json = item.to_json(current_user)
          previous_request = item.item_requests.find_by(user_id: current_user.id)
          current_request = item.item_requests.find_by(friend_id: current_user.id)
          json[:attributes]['total-price'] = previous_request.price if previous_request
          json[:attributes]['expected-price'] = (item.ref_price || current_request.price) if current_request

          next_request = item.item_requests.find_by(friend_id: current_user.id, status: [:pending, :accepted, :reserved])
          user_name = helpers.target_user_name(current_user.id, next_request.user_id) if next_request
          json[:attributes]['target-user-name'] = user_name if user_name
          json
        }

        if key.nil? || value.find{|r| r[:attributes]['chain_status'] == 'completed'}
          result.push(items)
        else
          order = Order.find(key)
          ready = order.item_requests.reject{|req| ["accepted", "cancelled"].include?(req.request_contract.status)}.length > 0 ? false : true
          order = order.as_json
          order["is_ready"] = ready
          result.push({order: order, items: items})
        end
      end

      without_requests = Inventory.where("user_id = #{current_user.id} AND (status = 2) AND quantity > 0 
      AND (SELECT COUNT(id) FROM request_contracts WHERE request_contracts.inventory_id = inventories.id) = 0")

      if without_requests.length > 0
        result.push(without_requests.map { |item| item.to_json(current_user) }.compact)
      end

      render json: {
        data: result
      }, status: 200
    end

    # GET: /v1/items/shipped
    def shipped
      items = ItemRequest.with_inventory_data
        .select("item_requests.*")
        .where("
          (item_requests.friend_id = #{current_user.id}) AND 
          item_requests.shipped_at IS NOT NULL AND
          item_requests.status = 2
        ").uniq
      items = items.uniq{ |item| item.request_contract_id}

      items = items.map do |item|
        json = item.to_json(current_user)
        previous_request = item.request_contract.item_requests.find_by(user_id: current_user.id)
        current_request = item.request_contract.item_requests.find_by(friend_id: current_user.id)
        json[:attributes]['total-price'] = previous_request.price if previous_request
        json[:attributes]['expected-price'] = (item.inventory.ref_price || current_request.price) if current_request
        # binding.pry
        json[:id] = item.inventory.id
        json[:attributes]['signed'] = item.signed_at?
        json
      end

      result = []
      items = items.group_by{|i| i[:attributes]["order"]}
      items.each do |key, value|
        if key.nil?
          result.push(value)
        else
          res = Order.find(key).as_json
          result.push({order: res, items: value})
        end
      end

      render json: {
        data: result
      }, status: 200
    end

    private
    def notify_request_chain!(request_contract)
      metadata = { request_contract_id: request_contract.id, quantity: request_contract.quantity.to_f }

      request_contract.item_requests.includes(:user, :friend).find_each do |chain_request|
        next unless chain_request.user && chain_request.friend

        Notifications.publish!(
          event:      :request_created,
          actor:      chain_request.user,
          recipients: [chain_request.friend],
          resource:   chain_request,
          metadata:   metadata
        )
      end
    end

    def serialize_request_result(request)
      request.reload
      contract = request.request_contract
      {
        id: request.id,
        status: request.status,
        order_id: request.order_id,
        contract_id: contract.id,
        contract_status: contract.status,
        inventory_id: contract.inventory_id,
        shipped_at: request.shipped_at,
        signed_at: request.signed_at,
        accepted_at: request.accepted_at,
      }
    end

    def request_params
      params.require(:request).permit(:quantity, :price, :unit)
    end

    def reserve_params
      params.permit(:inventory_id, :user_id, :quantity, :price)
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
