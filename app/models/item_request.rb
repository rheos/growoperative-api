class ItemRequest < ApplicationRecord
  belongs_to :user
  belongs_to :friend, :class_name => 'User'
  belongs_to :request_contract
  has_one    :inventory, through: :request_contract
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_many   :order_contents, dependent: :destroy


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
      true
    end
    true
  end

  def sign
    self.update(signed_at: DateTime.now)
    # change inventory ownership and price
    next_request = ItemRequest.find_by(request_contract_id: request_contract.id, friend_id: self.user_id)
    # next_price = next_request ? next_request.price : self.price
    self.inventory.update(user_id: self.user_id, ref_id: nil, price: self.price)
    # Note: ref_id is disabled because inventory will not be merged with original if contract will be cancelled
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
        'owner-id' => self.inventory.user_id
      }
    }
  end
end
