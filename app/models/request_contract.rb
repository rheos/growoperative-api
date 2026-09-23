class RequestContract < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :item_requests, dependent: :destroy
  has_one :inventory, primary_key: 'inventory_id', foreign_key: 'id'
  
  enum status: [ :pending, :accepted, :completed, :cancelled ]

  with_options allow_nil: true, numericality: { greater_than: 0 } do
    validates :estimated_weight
    validates :actual_weight
  end
  validate :weight_only_on_variable_weight_lines

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

  # --- Variable-weight ("buy a share") lines --------------------------------
  #
  # `quantity` is a share count here, not pounds. Pricing runs on weight, which
  # is an estimate at reserve and a real number only once the carcass is on the
  # scale. See the migration that added these columns for why the two are kept
  # apart.

  def variable_weight?
    item&.per_weight? || false
  end

  # True while a share has been claimed but never weighed. The order cannot ship
  # in this state, which is what stops settlement ever reading an estimate.
  def weight_pending?
    variable_weight? && actual_weight.nil?
  end

  # What the settlement sum multiplies the per-unit price by. Fixed-price lines
  # bill on quantity exactly as before; a weighed line bills on real pounds.
  def settlement_quantity
    variable_weight? ? actual_weight : quantity
  end

  # Effective per-pound rate for this line, after the on-the-rail discount the
  # buyer picked at reserve.
  def billed_rate
    return nil unless variable_weight?
    item.billed_rate(on_the_rail: on_the_rail)
  end

  def finalize_weight!(weight)
    raise ArgumentError, 'Not a variable-weight line' unless variable_weight?

    update!(actual_weight: weight, weight_finalized_at: Time.current)
  end

  private

  def weight_only_on_variable_weight_lines
    return if variable_weight?
    return if estimated_weight.blank? && actual_weight.blank?

    errors.add(:actual_weight, 'only applies to variable-weight listings')
  end

  def resolve_hop_notifications
    return unless cancelled? || completed?
    item_requests.find_each { |ir| Notifications.resolve!(ir) }
  end
end
