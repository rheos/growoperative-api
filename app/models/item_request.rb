class ItemRequest < ApplicationRecord
  belongs_to :user
  belongs_to :friend, :class_name => 'User'
  belongs_to :request_contract
  has_one    :inventory, through: :request_contract
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_one    :order, primary_key: 'order_id', foreign_key: 'id'


  #callbacks

  #attribs
  enum status: [ :pending, :accepted, :completed, :cancelled, :reserved ]

  scope :with_inventory_data, -> { joins("INNER JOIN `request_contracts` ON `request_contracts`.`id` = `item_requests`.`request_contract_id` INNER JOIN `inventories` ON `inventories`.`id` = `request_contracts`.`inventory_id`") }

  def accept_request
    prev_status = self.status
    self.update(status: :accepted, accepted_at: DateTime.now)

    # mark next request for sent 
    request = ItemRequest.find_by(request_contract_id: self.request_contract_id, user_id: self.friend_id)
    unless request.nil?
      request.sent = 1
      request.save!
    end

    # or request is accepted by the inventory owner
    pending_size = ItemRequest.where("request_contract_id = #{self.request_contract_id} AND status <> 1").size
    if self.step == 1 || pending_size == 0
      self.update(sent: true) if (prev_status == "reserved" || self.step == 1)
      if(prev_status == "pending")
      #reserve new inventory
        reserved = Inventory.new do |m|
          m.item_id = self.inventory.item_id
          m.user_id = self.inventory.user_id
          m.price = self.inventory.price
          m.quantity = self.request_contract.quantity
          m.ref_id = self.inventory.id #ref_id is pointing to previous inventory, which is needs do be restored
          m.status = :reserved
          m.gallery_map = self.inventory.gallery_map
          m.save!
        end

        # decrease origin inventory quantity
        quantity_left = self.inventory.quantity - self.request_contract.quantity
        if self.request_contract.unit && self.request_contract.unit.to_i != self.request_contract.inventory.item.item_unit_id
          request_unit = ItemUnit.find(self.request_contract.unit.to_i)
          self_unit = self.request_contract.inventory.item.item_unit
          quantity_left = self.inventory.quantity - (self.request_contract.quantity * request_unit.equivalent)/self_unit.equivalent

          converted_item = Item.create(self.inventory.item.attributes.merge({:unit => request_unit.unit_name, :id => nil}))
          reserved.update(item_id: converted_item.id)
        end
        self.inventory.update(quantity: quantity_left)

        # update inventory status if all item requests are accepted
        self.request_contract.update(status: :accepted) if pending_size == 0
        # bind contract to a new reserved inventory and update status
        RequestContract.find_by(id: self.request_contract_id).update(inventory_id: reserved.id)

        # create or find order if there are any request_contract with same relation present
        order = Order.where(user_id: self.user_id, friend_id: self.friend_id, order_status: 0)
        return { message: 'Please, choose order to assign' } if order.length > 1
        order = order[0]
        if !order
          order = Order.create(user_id: self.user_id, friend_id: self.friend_id, order_status: 0, order_total: self.request_contract.quantity)
          order.update(order_label: 'Order ' + order.id.to_s)
        else
          order.update(order_total: (order.order_total || 0) + self.request_contract.quantity)
        end
        self.update(order_id: order.id)
      else
        order = Order.find_by(user_id: self.user_id, friend_id: self.friend_id, order_status: 0)
        if !order
          order = Order.create(user_id: self.user_id, friend_id: self.friend_id, order_status: 0, order_total: self.request_contract.quantity)
          order.update(order_label: 'Order ' + order.id.to_s)
        else
          order.update(order_total: (order.order_total || 0) + self.request_contract.quantity)
        end
        self.update(order_id: order.id)
        self.request_contract.update(status: :accepted) if pending_size == 0
      end
    end
    true
  end

  def ship (multi = false)
    self.shipped_at = DateTime.now
    self.status = :completed
    # self.order.update(order_total: self.order.order_total - self.request_contract.quantity) if !multi
    # self.order_id = nil if !multi
    self.save!
  end

  def sign (multi = false)
    self.update(signed_at: DateTime.now)
    # change inventory ownership and price
    self.inventory.update(user_id: self.user_id, ref_id: nil, price: self.price)
    # Note: ref_id is disabled because inventory will not be merged with original if contract will be cancelled
  
    # Create or find order if current request isn't last in chain and there are requests with same relation present
    next_request = ItemRequest.find_by(request_contract_id: self.request_contract_id, friend_id: self.user_id)

    if next_request
      order = Order.find_by(user_id: next_request.user_id, friend_id: next_request.friend_id, order_status: 0)
      if !order
        order = Order.create(user_id: next_request.user_id, friend_id: next_request.friend_id, order_status: 0)
        order.update(order_label: 'Order ' + order.id.to_s)
        next_request.update(order_id: order.id)
      else
        order.update(order_total: (order.order_total || 0) + self.request_contract.quantity)
      end
    end

    # Update current contract step and finish contract, if all steps are done
    request_contract = self.request_contract

    request_contract.current_step += 1
    if request_contract.current_step == request_contract.steps
      request_contract.status = :completed
      inventory.update(status: :unavailable)
    end

    request_contract.save!
  end

  def calculate_cahin_status
    contract = self.request_contract
    return contract.status if ['accepted', 'completed', 'cancelled'].include?(contract.status)
    if contract.item_requests.where(status: :pending).count > 0
      return 'partially'
    else
      return 'pending'
    end

  end

  def to_json(current_user)
    target_user_id = self.user_id == current_user.id ? self.friend_id : self.user_id
    {
      :id => self.id, 
      :attributes => {
        'quantity' => self.request_contract.quantity, 
        'total-price' => self.price,
        'user-id' => target_user_id,
        'target-user-id' => target_user_id,
        'target-user-name' => ApplicationController.helpers.target_user_name(current_user.id, target_user_id),
        'category-id' => self.inventory.item.category_id,
        'name' => self.inventory.item.name,
        'grade-id' => self.inventory.item.grade_id,
        'item-unit-id' => self.inventory.item.item_unit_id,
        'inventory_id' => self.inventory.id,
        'unit-name' => self.inventory.item.item_unit.unit_name,
        'item-name-id' => self.inventory.item.item_name_id,
        'date-available' => self.inventory.item.date_available,
        'total-quantity' => self.inventory.quantity,
        'organic' => self.inventory.item.organic,
        'created-at' => self.created_at,
        'sent' => self.user_id == current_user.id,
        'avatars' => ((self.inventory.avatars.length > 0 && self.inventory.avatars) || self.inventory.item.avatars || []).map { |i| '/v1'+i.url.gsub(Rails.root.to_s, '') },
        'owner-id' => self.inventory.user_id,
        'producer' => self.inventory.item.producer_id,
        'order' => self.order_id,
        'contract_chain_status' => calculate_cahin_status,
        'unit' => self.request_contract.unit
      }
    }
  end
end
