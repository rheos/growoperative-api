class ItemRequest < ApplicationRecord
  belongs_to :user
  belongs_to :friend, :class_name => 'User'
  belongs_to :inventory
  belongs_to :request_contract
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_many   :order_contents, dependent: :destroy

  #callbacks
  after_update :update_inventory

  #attribs
  enum status: [ :pending, :accepted, :completed, :cancelled ]

  # update inventory after all requests are accepted
  def update_inventory
    unless self.accepted?
      return
    end

    # mark request for sent 
    request = ItemRequest.find_by(request_contract_id: self.request_contract_id, user_id: self.friend_id)
    unless request.nil?
      request.sent = 1
      request.save!
    end
    
    # check if all item requests were accepted
    if ItemRequest.where("request_contract_id = #{self.request_contract_id} AND status <> 1").size > 0
      return
    end

    # decrease quantity
    self.inventory.quantity -= self.request_contract.quantity
    unless self.inventory.save!
      return
    end

    # create a new inventory
    reserved = Inventory.new do |m|
      m.item_id = self.inventory.item_id
      m.user_id = self.inventory.user_id
      m.price = self.inventory.price
      m.quantity = self.request_contract.quantity
      m.ref_id = self.request_contract_id
      m.status = :reserved
      m.save
    end

    # mark request contract as accepted
    self.request_contract.status = :accepted
    self.request_contract.save

  end

  def to_json(current_user)
    target_user_id = self.user_id == current_user.id ? self.friend_id : self.user_id
    {
      :id => self.id, 
      :attributes => {
        'quantity' => self.quantity, 
        'total-price' => self.price, 
        'user-id' => target_user_id,
        'target-user-id' => target_user_id, 
        'target-user-name' => ApplicationController.helpers.target_user_name(current_user.id, target_user_id),
        'category-id' => self.inventory.item.category_id, 
        'name' => self.inventory.item.name, 
        'grade-id' => self.inventory.item.grade_id,
        'item-unit-id' => self.inventory.item.item_unit_id, 
        'unit-name' => self.inventory.item.item_unit.unit_name, 
        'item-name-id' => self.inventory.item.item_name_id, 
        'date-available' => self.inventory.item.date_available, 
        'total-quantity' => self.inventory.quantity, 
        'organic' => self.inventory.item.organic, 
        'created-at' => self.created_at, 
        'sent' => self.user_id == current_user.id,
      }
    }
  end
end
