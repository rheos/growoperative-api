# Groups item_requests between the same buyer (user_id) and seller (friend_id).
# Lifecycle: pending → shipped → signed, then settlement negotiation.
#
# INVARIANT: An order is atomic — it ships as a whole. Once any item_request
# on the order is shipped/completed, no new items may be added. New items
# for the same buyer-seller pair go on a fresh order.
class Order < ApplicationRecord
  has_many :item_requests, primary_key: 'id', foreign_key: 'order_id', dependent: :destroy
  has_many :request_contracts, through: :item_requests
  has_many :inventories, through: :request_contracts
  enum order_status: [ :pending, :shipped, :signed ]

  # Find or create a pending order suitable for new items.
  # Skips any pending order that already has completed (shipped) requests,
  # since those are effectively "done" even if the order-level status
  # hasn't caught up. Used by ItemRequest#accept_request, #sign (chain
  # cascading), and ItemRequestsController#reserve.
  #
  # CONCURRENCY: two requests accepted at the same instant (e.g. the "accept
  # all" button firing parallel accepts) both ran find-then-create and each
  # created an order, producing duplicate pending orders for one pair. We
  # serialize per seller with a FOR UPDATE row lock. A row lock (unlike a MySQL
  # named lock) is held until the surrounding transaction commits, so the order
  # is durable before the next caller proceeds. The candidates query is then a
  # LOCKING read (.lock) so that next caller sees the just-committed order — a
  # plain read would use its REPEATABLE READ snapshot (taken before the first
  # committed) and miss it, recreating the bug.
  def self.find_or_create_pending(buyer_id, seller_id)
    transaction do
      # Lock a stable row both concurrent callers contend on; released on commit.
      User.where(id: seller_id).lock(true).first
      candidates = Order.where(user_id: buyer_id, friend_id: seller_id, order_status: 0).lock(true)
      order = candidates.to_a.find { |o| !o.item_requests.exists?(status: [:completed]) }
      unless order
        order = Order.create!(user_id: buyer_id, friend_id: seller_id, order_status: :pending)
        order.update!(order_label: 'Order ' + order.id.to_s)
      end
      order
    end
  end

  def remove_request (id)
    # self.item_requests.find(id)
  end

  # Central state machine for order actions. Called via PATCH /v1/orders/:id.
  # Returns false on permission/guard failure.
  def apply_action (action, user_id)
    case action[:action_name]

    # --- Shipping & receiving ---

    when 'sign'
      # Only the buyer (user_id) can sign, and only after shipment
      return false if (user_id.to_s != self.user_id || self.order_status != "shipped")
      self.item_requests.each do |item_request|
        item_request.sign if !item_request.signed_at
      end
      self.update(signed_on: DateTime.now, order_status: :signed)

    when 'ship'
      # Only the seller (friend_id) can ship; all contracts must be accepted
      return false if (user_id.to_s != self.friend_id || self.order_status == "shipped") || self.item_requests.find{|item_request| item_request.request_contract.status != "accepted"}
      # Transaction ensures item_requests and order status update atomically —
      # if any item fails to ship, the order stays pending (no split state).
      ActiveRecord::Base.transaction do
        self.item_requests.each do |item_request|
          item_request.ship if !item_request.shipped_at
        end
        attrs = { shipped_on: DateTime.now, order_status: :shipped }
        if action[:settlement_type].present? && %w[cash credit].include?(action[:settlement_type])
          attrs[:settlement_type] = action[:settlement_type]
          attrs[:settlement_proposed_by] = user_id
          attrs[:settlement_status] = 'proposed'
        end
        self.update!(attrs)
      end

    # --- Item management ---

    when 'remove_item'
      item = self.item_requests.joins(:request_contract).where("request_contracts.inventory_id = #{action[:item_id]}")
      return false if !item
      item.update(order_id: nil)
      # Use delete instead of destroy to avoid dependent: :destroy cascading
      # to the item requests we just detached (Rails caches the association)
      Order.delete(self.id) if ItemRequest.where(order_id: self.id).count == 0
      true

    when 'add_item'
      # Guard: only pending orders with no completed requests accept new items
      return false unless self.order_status == 'pending'
      return false if self.item_requests.exists?(status: [:completed])
      item_requests = ItemRequest.joins(:request_contract).where("request_contracts.inventory_id = #{action[:item_id]} AND item_requests.status = 1")
      return false if !item_requests.first
      item_request = item_requests.find{ |i| i.friend_id.to_s == user_id.to_s || i.friend_id.to_s == self.friend_id}
      return false if !item_request
      item_request.update(order_id: self.id)

    # --- Settlement negotiation ---

    when 'respond_settlement'
      # Receiver (user_id side) responds to shipper's preference
      return false unless self.order_status == 'shipped' || self.order_status == 'signed'
      return false unless user_id.to_s == self.user_id  # only the receiver responds
      return false unless %w[cash credit].include?(action[:settlement_type])

      if action[:settlement_type] == self.settlement_type
        # Agrees with shipper — proceed to execution
        self.update(settlement_status: 'agreed')
      elsif action[:settlement_type] == 'cash'
        # Receiver offers cash when shipper wanted credit — auto-accept (cash always OK)
        self.update(
          settlement_counter_type: 'cash',
          settlement_counter_by: user_id,
          settlement_type: 'cash',  # override to agreed type
          settlement_status: 'agreed'
        )
      else
        # Receiver requests credit when shipper wanted cash — needs shipper approval
        self.update(
          settlement_counter_type: 'credit',
          settlement_counter_by: user_id,
          settlement_status: 'countered'
        )
      end

    when 'approve_counter'
      # Shipper approves receiver's counter-proposal (credit when shipper wanted cash)
      return false unless self.settlement_status == 'countered'
      return false unless user_id.to_s == self.friend_id  # only shipper approves
      self.update(
        settlement_type: self.settlement_counter_type,
        settlement_status: 'agreed'
      )

    when 'deny_counter'
      # Shipper denies receiver's credit counter — falls back to cash
      return false unless self.settlement_status == 'countered'
      return false unless user_id.to_s == self.friend_id  # only shipper denies
      self.update(
        settlement_type: 'cash',
        settlement_counter_type: nil,
        settlement_counter_by: nil,
        settlement_status: 'agreed'
      )

    when 'record_cash_payment'
      # Payer records how much they paid
      return false unless self.settlement_status == 'agreed' && self.settlement_type == 'cash'
      return false unless user_id.to_s == self.user_id  # receiver/buyer pays
      return false unless action[:cash_amount].present?
      self.update(
        cash_amount: action[:cash_amount].to_f,
        cash_paid_by: user_id,
        settlement_status: 'cash_pending_confirmation'
      )

    when 'confirm_cash_receipt'
      # Payee confirms they received the cash
      return false unless self.settlement_status == 'cash_pending_confirmation'
      return false unless user_id.to_s == self.friend_id  # shipper/seller confirms
      self.update(
        cash_confirmed_by: user_id,
        settlement_status: 'settled'
      )

    when 'execute_credit'
      # Both agreed on credit — execute via trustline
      return false unless self.settlement_status == 'agreed' && self.settlement_type == 'credit'
      return false unless user_id.to_s == self.user_id || user_id.to_s == self.friend_id
      begin
        execute_credit_payment!
      rescue => e
        errors.add(:base, e.message)
        return false
      end
      self.update(settlement_status: 'settled')

    when 'propose_settlement'
      # Legacy: kept for backward compat but ship now handles this
      return false unless user_id.to_s == self.user_id || user_id.to_s == self.friend_id
      return false unless self.order_status == 'signed'
      return false unless %w[cash credit].include?(action[:settlement_type])
      self.update(
        settlement_type: action[:settlement_type],
        settlement_status: 'proposed',
        settlement_proposed_by: user_id
      )

    when 'accept_settlement'
      # Legacy: kept for backward compat
      return false unless self.settlement_status == 'proposed'
      return false if user_id == self.settlement_proposed_by
      return false unless user_id.to_s == self.user_id || user_id.to_s == self.friend_id
      if self.settlement_type == 'credit'
        begin
          execute_credit_payment!
        rescue => e
          errors.add(:base, e.message)
          return false
        end
      end
      self.update(settlement_status: 'accepted')

    else
      return false
    end
  end

  private

  # The actual dollar amount owed — sum of (price × quantity) for each item.
  def settlement_amount
    self.item_requests
      .joins(:request_contract)
      .sum('item_requests.price * request_contracts.quantity')
  end

  # Ensure a trustline exists between the two parties with enough credit,
  # then execute the payment. Both parties agreed on credit so the limit
  # should auto-increase if needed — the agreement IS the authorization.
  def execute_credit_payment!
    amount = settlement_amount
    from_user = User.find(self.user_id)
    to_user = User.find(self.friend_id)

    trustline = Trustline.between_users(from_user, to_user).first
    if trustline.nil?
      trustline = Trustline.create!(
        user_a: from_user,
        user_b: to_user,
        credit_limit_a_to_b: amount,
        credit_limit_b_to_a: 0,
        current_balance: 0,
        is_active: true
      )
    else
      available = trustline.available_credit_for(from_user)
      if available < amount
        shortfall = amount - available
        if from_user.id == trustline.user_a_id
          trustline.update!(credit_limit_a_to_b: trustline.credit_limit_a_to_b + shortfall)
        else
          trustline.update!(credit_limit_b_to_a: trustline.credit_limit_b_to_a + shortfall)
        end
      end
    end

    # Mirror trustline creation/update to FOAF
    Foaf::ShadowHooks.after_trustline_save(trustline, from_user)

    Trustline.execute_payment_path(
      [from_user, to_user],
      amount,
      description: "Settlement for #{self.order_label}",
      order: self
    )
    # Payment is mirrored by process_payment! inside execute_payment_path
  end
end
