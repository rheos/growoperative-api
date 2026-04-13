class PendingPayment < ApplicationRecord
  belongs_to :from_user, class_name: 'User'
  belongs_to :to_user, class_name: 'User'
  belongs_to :trustline

  enum status: [:pending, :confirmed, :rejected, :cancelled]

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validate :users_on_trustline, on: :create
  validate :credit_available, on: :create

  scope :for_user, ->(user) { where('from_user_id = ? OR to_user_id = ?', user.id, user.id) }

  def confirm!
    raise 'Payment is not pending' unless pending?
    raise 'Insufficient credit' unless trustline.can_handle_payment?(amount, from_user)

    transaction do
      new_balance = trustline.process_payment!(
        amount,
        from_user,
        to_user,
        description: description || "Payment from #{from_user.user_name} to #{to_user.user_name}"
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
    raise 'Payment is not pending' unless pending?

    update!(
      status: :rejected,
      rejected_reason: reason,
      resolved_at: Time.current
    )
  end

  def cancel!
    raise 'Payment is not pending' unless pending?

    update!(
      status: :cancelled,
      resolved_at: Time.current
    )
  end

  private

  def users_on_trustline
    return unless trustline && from_user && to_user
    unless trustline.involves_users?(from_user, to_user)
      errors.add(:base, 'Users must both be on the trustline')
    end
  end

  def credit_available
    return unless trustline && from_user && amount
    unless trustline.can_handle_payment?(amount, from_user)
      errors.add(:amount, 'exceeds available credit')
    end
  end
end
