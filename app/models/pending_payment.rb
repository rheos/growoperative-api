class PendingPayment < ApplicationRecord
  belongs_to :from_user, class_name: 'User'
  belongs_to :to_user, class_name: 'User'
  belongs_to :trustline

  enum status: [:pending, :confirmed, :rejected, :cancelled, :paid_pending_confirmation]
  enum kind: [:payment, :request]

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate :users_on_trustline, on: :create

  scope :for_user, ->(user) { where('from_user_id = ? OR to_user_id = ?', user.id, user.id) }

  # Debtor (to_user on a request) marks that they've paid in cash. Moves the
  # record to paid_pending_confirmation; the creditor (from_user) must still
  # confirm receipt before the trustline updates.
  def mark_paid!
    raise 'Only request-kind payments can be marked paid' unless request?
    raise 'Payment is not pending' unless pending?

    update!(status: :paid_pending_confirmation, paid_at: Time.current)
  end

  # Settles the trustline. Behavior depends on kind:
  # - payment: from_user is the payer who initiated; to_user (payee) confirmed receipt.
  # - request: from_user is the creditor who initiated; to_user (debtor) marked paid;
  #   from_user is now confirming they received the cash.
  # In both cases the trustline math is the same: settle_payment!(payer, payee).
  def confirm!
    payer, payee = case kind
                   when 'payment'
                     raise 'Payment is not pending' unless pending?
                     [from_user, to_user]
                   when 'request'
                     raise 'Request not awaiting confirmation' unless paid_pending_confirmation?
                     [to_user, from_user]
                   end

    transaction do
      new_balance = trustline.settle_payment!(
        amount,
        payer,
        payee,
        description: description || default_description(payer, payee)
      )

      update!(
        status: :confirmed,
        confirmed_at: Time.current,
        resolved_at: Time.current
      )

      new_balance
    end
  end

  def reject!(reason: nil)
    raise 'Cannot reject a resolved payment' if resolved?

    update!(
      status: :rejected,
      rejected_reason: reason,
      resolved_at: Time.current
    )
  end

  def cancel!
    raise 'Cannot cancel a resolved payment' if resolved?

    update!(
      status: :cancelled,
      resolved_at: Time.current
    )
  end

  # The party who initiated the record (creditor for request, payer for payment).
  def initiator
    from_user
  end

  def initiator_id
    from_user_id
  end

  # The party who must take the next action.
  def awaiting_user
    case [kind, status]
    when ['payment', 'pending']                  then to_user
    when ['request', 'pending']                  then to_user
    when ['request', 'paid_pending_confirmation'] then from_user
    end
  end

  def open?
    pending? || paid_pending_confirmation?
  end

  private

  def resolved?
    confirmed? || rejected? || cancelled?
  end

  def default_description(payer, payee)
    case kind
    when 'payment'
      "Payment from #{payer.user_name} to #{payee.user_name}"
    when 'request'
      "Cash settlement from #{payer.user_name} to #{payee.user_name}"
    end
  end

  def users_on_trustline
    return unless trustline && from_user && to_user
    unless trustline.involves_users?(from_user, to_user)
      errors.add(:base, 'Users must both be on the trustline')
    end
  end
end
