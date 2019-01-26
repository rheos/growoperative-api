class RequestContract < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :item_requests, dependent: :destroy
  
  enum status: [ :pending, :accepted, :cancelled, :reserved, :settled ]

  # callbacks
  after_update :set_requests_settled

  def set_requests_settled
    unless self.status == 'pending'
      #mark others requests as settled
      ItemRequest.where("request_contract_id = #{self.id}").update_all(status: self.status)
    end

    # restore inventory
    if self.cancelled? && Inventory.where("ref_id = #{self.id}").size > 0
      inventory = Inventory.find(self.inventory_id)
      inventory.quantity += self.quantity
      inventory.save

      # remove old
      Inventory.where("ref_id = #{self.id}").destroy_all
    end
  end
end
