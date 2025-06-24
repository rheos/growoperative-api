# TrustlineTransaction Model - Transaction History and Audit Trail
#
# Records all movements of credit through the trustline network. Every payment,
# settlement, adjustment, or reversal creates a transaction record for complete
# audit trail and balance reconciliation.
#
# Transaction Types:
# - 'payment'    - Regular payment between users
# - 'settlement' - External settlement (outside the app)
# - 'adjustment' - Manual balance correction
# - 'reversal'   - Reversal of a previous transaction
#
# Balance Tracking:
# - Each transaction records the trustline balance after the transaction
# - This enables point-in-time balance reconstruction and audit trails
# - Reversals create new transactions rather than deleting original ones

class TrustlineTransaction < ApplicationRecord
  # === ASSOCIATIONS ===
  belongs_to :trustline
  belongs_to :originating_request, class_name: 'ItemRequest', optional: true
  belongs_to :order, optional: true
  belongs_to :initiated_by, class_name: 'User'
  
  # === VALIDATIONS ===
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :transaction_type, presence: true, inclusion: { 
    in: %w[payment settlement adjustment reversal], 
    message: "%{value} is not a valid transaction type" 
  }
  validates :balance_after, presence: true, numericality: true
  
  # === SCOPES ===
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
  
  # === TRANSACTION ANALYSIS METHODS ===
  
  # Determines the user who initiated/sent this transaction
  # For payments, this is the user who sent money
  # @return [User, nil] - The user who sent the payment
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
  
  # Determines the user who received this transaction
  # @return [User, nil] - The user who received the payment
  def to_user
    return nil unless trustline && from_user
    trustline.other_user(from_user)
  end
  
  # Returns the transaction amount from a specific user's perspective
  # Positive amounts represent money spent, negative amounts represent money received
  # @param user [User] - The user whose perspective to show
  # @return [Numeric] - The amount from user's perspective
  def user_perspective_amount(user)
    return amount if initiated_by == user
    -amount # If user received the payment, show as negative from their spending perspective
  end
  
  # === TRANSACTION REVERSAL METHODS ===
  
  # Reverses this transaction by creating a counteracting transaction
  # This maintains full audit trail while undoing the balance effects
  # @param reason [String] - Optional reason for the reversal
  # @return [TrustlineTransaction, false] - The reversal transaction or false if failed
  def reverse!(reason: nil)
    return false if is_reversed?
    
    transaction do
      # Create a reversal transaction that counteracts this one
      reversal = trustline.trustline_transactions.create!(
        amount: amount,
        description: "Reversal: #{reason || 'Transaction reversed'}",
        transaction_type: 'reversal',
        initiated_by: initiated_by,
        balance_after: trustline.current_balance - (balance_after - trustline.current_balance),
        originating_request: originating_request,
        order: order
      )
      
      # Mark original transaction as reversed
      update!(is_reversed: true)
      
      # Update trustline balance to remove the effect of the original transaction
      balance_change = balance_after - trustline.current_balance
      trustline.update!(current_balance: trustline.current_balance - balance_change)
      
      reversal
    end
  end
end 