class TrustlineTransaction < ApplicationRecord
  belongs_to :trustline
  belongs_to :originating_request, class_name: 'ItemRequest', optional: true
  belongs_to :order, optional: true
  belongs_to :initiated_by, class_name: 'User'
  
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, inclusion: { 
    in: %w[payment settlement adjustment reversal], 
    message: "%{value} is not a valid transaction type" 
  }
  validates :balance_after, presence: true, numericality: true
  
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) do
    joins(:trustline).where(
      "(trustlines.user_a_id = ? OR trustlines.user_b_id = ?) OR initiated_by_id = ?", 
      user.id, user.id, user.id
    )
  end
  scope :payments, -> { where(transaction_type: 'payment') }
  scope :settlements, -> { where(transaction_type: 'settlement') }
  scope :not_reversed, -> { where(is_reversed: false) }
  
  def from_user
    return nil unless originating_request
    
    # Determine direction based on transaction type and trustline structure
    if transaction_type == 'payment'
      initiated_by
    else
      # For other transaction types, we may need more logic
      initiated_by
    end
  end
  
  def to_user
    return nil unless trustline && from_user
    trustline.other_user(from_user)
  end
  
  def user_perspective_amount(user)
    return amount if initiated_by == user
    -amount # If user received the payment, show as negative from their spending perspective
  end
  
  def reverse!(reason: nil)
    return false if is_reversed?
    
    transaction do
      # Create a reversal transaction
      reversal = trustline.trustline_transactions.create!(
        amount: amount,
        description: "Reversal: #{reason || 'Transaction reversed'}",
        transaction_type: 'reversal',
        initiated_by: initiated_by,
        balance_after: trustline.current_balance - (balance_after - trustline.current_balance),
        originating_request: originating_request,
        order: order
      )
      
      # Mark original as reversed
      update!(is_reversed: true)
      
      # Update trustline balance
      balance_change = balance_after - trustline.current_balance
      trustline.update!(current_balance: trustline.current_balance - balance_change)
      
      reversal
    end
  end
end 