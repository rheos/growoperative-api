class RequestContract < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :item_requests, dependent: :destroy
  has_one :inventory, primary_key: 'inventory_id', foreign_key: 'id'
  
  enum status: [ :pending, :accepted, :completed, :cancelled ]

  # callbacks
  after_update :update_callback
  # update_callback fans hop statuses with update_all, which bypasses ItemRequest
  # callbacks — this contract-level hook is what resolves hop notifications on
  # chain cancellation and sign-completion, after the transaction commits.
  after_commit :resolve_hop_notifications, on: :update

  def update_callback
    if self.completed? || self.cancelled?
      self.item_requests.update_all(status: self.status)
    end


    # restore inventory
    # origin_inventory = Inventory.find_by(id: self.inventory.ref_id)
    # if self.cancelled? && origin_inventory
    #   origin_inventory.quantity += self.quantity
    #   origin_inventory.save
    #   # remove reserved inventory
    #   self.inventory.destroy
    # end
  end

  private

  def resolve_hop_notifications
    return unless cancelled? || completed?
    item_requests.find_each { |ir| Notifications.resolve!(ir) }
  end
end
