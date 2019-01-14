class ItemRequest < ApplicationRecord
  belongs_to :user
  belongs_to :friend, :class_name => 'User'
  belongs_to :item
  belongs_to :request_contract
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_many   :order_contents, dependent: :destroy

  #callbacks
  after_update :update_inventory

  #attribs
  enum status: [ :pending, :accepted, :cancelled ]

  # update inventory after all requests are accepted
  def update_inventory
    unless self.status == 'accepted'
      return
    end
    # check if all item requests were accepted
    if ItemRequest.where(request_contract_id: self.request_contract_id, status: :pending).size > 0
      return
    end

    # check if item inventory exists
    inventory = Inventory.find_by(item_id: self.item_id, user_id: self.item.user_id, status: :available)
    if inventory.nil?
      return
    end

    # decrease quantity
    inventory.quantity -= self.request_contract.quantity
    unless inventory.save!
      return
    end

    # create a new inventory
    reserved = Inventory.new do |m|
      m.item_id = self.item.id
      m.user_id = self.item.user_id
      m.price = self.item.price
      m.quantity = self.request_contract.quantity
      m.ref_id = self.request_contract_id
      m.status = :reserved
      m.save
    end

    # mark request contract as accepted
    self.request_contract.status = :accepted
    self.request_contract.save
  end
end
