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
  enum status: [ :pending, :accepted, :completed, :cancelled ]

  scope :with_inventory_data, -> { joins("INNER JOIN `request_contracts` ON `request_contracts`.`id` = `item_requests`.`request_contract_id` INNER JOIN `inventories` ON `inventories`.`id` = `request_contracts`.`inventory_id`") }

  def accept_request
    self.update(status: :accepted, accepted_at: DateTime.now)

    # mark next request for sent 
    request = ItemRequest.find_by(request_contract_id: self.request_contract_id, user_id: self.friend_id)
    unless request.nil?
      request.sent = 1
      request.save!
    end
    
    # check if all item requests were accepted
    if ItemRequest.where("request_contract_id = #{self.request_contract_id} AND status <> 1").size == 0
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
      self.inventory.update(quantity: quantity_left)
     
      # bind contract to a new reserved inventory and update status
      self.request_contract.update(inventory_id: reserved.id, status: :accepted)

      # create or find order if there are any request_contract with same relation present
      # binding.pry
      parallel_request = ItemRequest.where("user_id = #{self.user_id} AND friend_id = #{self.friend_id} AND status = 1 AND signed_at IS NULL AND shipped_at IS NULL AND id != #{self.id}").first
      if parallel_request
        order = Order.find_by(user_id: self.user_id, friend_id: self.friend_id, order_status: 0)
        if !order
          order = Order.create(user_id: self.user_id, friend_id: self.friend_id, order_status: 0, order_label: self.inventory.item.name + ' order', order_total: self.request_contract.quantity + parallel_request.request_contract.quantity)
          parallel_request.update(order_id: order.id)
        else
          order.update(order_total: (order.order_total || 0) + self.request_contract.quantity)
        end
        self.update(order_id: order.id)
      end
      true
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
    next_parallel_request = ItemRequest.where("friend_id = #{self.user_id} AND status = 1 AND signed_at IS NULL AND shipped_at IS NULL AND id != #{next_request.id}").first if next_request

    if next_request && next_parallel_request
      order = Order.find_by(user_id: next_request.user_id, friend_id: next_request.friend_id, order_status: 0)
      if !order
        order = Order.create(user_id: next_request.user_id, friend_id: next_request.friend_id, order_status: 0, order_label: next_request.inventory.item.name + ' order')
        next_request.update(order_id: order.id)
        next_parallel_request.update(order_id: order.id)
      else
        order.update(order_total: (order.order_total || 0) + self.request_contract.quantity)
      end
    end

    # Update current contract step and finish contract, if all steps are done
    request_contract = self.request_contract

    request_contract.current_step += 1
    if request_contract.current_step == request_contract.steps
      request_contract.status = :completed
    end

    request_contract.save!
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
        'order' => self.order_id,
        'chain_status' => self.request_contract.status
      }
    }
  end
end
