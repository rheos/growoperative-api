class RequestContract < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :item_requests, dependent: :destroy
  has_one :inventory, foreign_key: "ref_id"
  
  enum status: [ :pending, :accepted, :completed, :cancelled ]

  # callbacks
  after_update :update_callback

  def update_callback
    if self.completed? || self.cancelled?
      ItemRequest.where("request_contract_id = #{self.id}").update_all(status: self.status)
    end

    # restore inventory
    current_inventory = Inventory.find(inventory_id)
    origin_inventory = Inventory.find_by(id: current_inventory.ref_id)
    if self.cancelled? && origin_inventory
      origin_inventory = Inventory.find(current_inventory.ref_id)
      origin_inventory.quantity += self.quantity
      origin_inventory.save

      # remove old
      current_inventory.destroy
    end
  end
end
