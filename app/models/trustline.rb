# Trustline Model - Core Mutual Credit System Implementation
#
# A Trustline represents a bidirectional credit relationship between two users.
# This is the foundation of the mutual credit system where users can extend
# credit limits to each other and make payments through the network.
#
# Key Concepts:
# - Each trustline has two credit limits (A→B and B→A)
# - Current balance tracks net position between users
# - Positive balance means user_a owes user_b
# - Negative balance means user_b owes user_a
# - Users can make payments up to their available credit limit
#
# Example:
#   Alice ←→ Bob trustline with limits: Alice $1000, Bob $500
#   If Alice pays Bob $300, balance becomes +$300 (Alice owes Bob)
#   Alice's available credit: $1000 - $300 = $700
#   Bob's available credit: $500 (unchanged, as he's owed money)

class Trustline < ApplicationRecord
  # === ASSOCIATIONS ===
  belongs_to :user_a, class_name: 'User'
  belongs_to :user_b, class_name: 'User'
  has_many :trustline_transactions, dependent: :destroy
  has_many :foaf_outbox_entries, dependent: :delete_all
  
  # === VALIDATIONS ===
  validates :credit_limit_a_to_b, :credit_limit_b_to_a, :current_balance, 
            presence: true, numericality: true
  validates :user_a_id, uniqueness: { scope: :user_b_id }
  validate :different_users
  validate :user_order_constraint
  validate :demo_boundary
  
  # === SCOPES ===
  scope :active, -> { where(is_active: true) }
  scope :for_user, ->(user) { where("user_a_id = ? OR user_b_id = ?", user.id, user.id) }
  scope :between_users, ->(user1, user2) do
    user_a_id, user_b_id = [user1.id, user2.id].sort
    where(user_a_id: user_a_id, user_b_id: user_b_id)
  end
  
  # === CALLBACKS ===
  before_validation :ensure_user_order, on: :create
  before_create :set_established_date
  after_save :enqueue_foaf_limit_update,
             if: :foaf_limit_publication_needed?
  
  # === CORE MUTUAL CREDIT METHODS ===
  
  # Returns the other user in this trustline relationship
  # @param current_user [User] - One of the users in the trustline
  # @return [User] - The other user in the trustline
  # @raise [ArgumentError] - If current_user is not part of this trustline
  def other_user(current_user)
    return user_b if current_user.id == user_a_id
    return user_a if current_user.id == user_b_id
    raise ArgumentError, "User #{current_user.id} is not part of this trustline"
  end

  private

  def foaf_limit_publication_needed?
    Foaf::Config.foaf_write_enabled? &&
      (previously_new_record? ||
       saved_change_to_credit_limit_a_to_b? ||
       saved_change_to_credit_limit_b_to_a?)
  end

  # Runs inside the Trustline save transaction. If Rails commits the limit,
  # the durable publication record commits with it; if Rails rolls back, both
  # roll back. A newer snapshot supersedes any older unposted value.
  def enqueue_foaf_limit_update
    FoafOutboxEntry.enqueue_trustline_update!(self)
  end

  public
  
  # Returns the credit limit that a specific user can borrow
  # @param user [User] - The user whose credit limit to retrieve
  # @return [BigDecimal] - The credit limit for this user
  # @raise [ArgumentError] - If user is not part of this trustline
  def credit_limit_for(user)
    return credit_limit_a_to_b if user.id == user_a_id
    return credit_limit_b_to_a if user.id == user_b_id
    raise ArgumentError, "User #{user.id} is not part of this trustline"
  end
  
  # Calculates how much credit a user has available to spend
  # Takes into account their credit limit and current balance
  # @param user [User] - The user whose available credit to calculate
  # @return [BigDecimal] - Available credit amount
  # @raise [ArgumentError] - If user is not part of this trustline
  def available_credit_for(user)
    if user.id == user_a_id
      # User A can borrow up to credit_limit_a_to_b
      # Positive balance means A owes B, so less available credit
      credit_limit_a_to_b - [current_balance, 0].max
    elsif user.id == user_b_id
      # User B can borrow up to credit_limit_b_to_a  
      # Negative balance means B owes A, so less available credit
      credit_limit_b_to_a - [-current_balance, 0].max
    else
      raise ArgumentError, "User #{user.id} is not part of this trustline"
    end
  end
  
  # Returns the current balance from a specific user's perspective
  # @param user [User] - The user whose perspective to show
  # @return [BigDecimal] - Balance (positive = user owes, negative = user is owed)
  # @raise [ArgumentError] - If user is not part of this trustline
  def balance_for(user)
    if user.id == user_a_id
      current_balance  # Positive = A owes B, Negative = B owes A
    elsif user.id == user_b_id
      -current_balance # From B's perspective, flip the sign
    else
      raise ArgumentError, "User #{user.id} is not part of this trustline"
    end
  end
  
  # Checks if this trustline can handle a payment of specified amount
  # @param amount [Numeric] - The payment amount to check
  # @param from_user [User] - The user making the payment
  # @return [Boolean] - Whether the payment can be processed
  def can_handle_payment?(amount, from_user)
    return false unless is_active?
    available_credit_for(from_user) >= amount
  end
  
  # Processes a payment through this trustline with full transaction recording
  # This is the core payment processing method that updates balances atomically
  # @param amount [Numeric] - The payment amount
  # @param from_user [User] - The user making the payment
  # @param to_user [User] - The user receiving the payment
  # @param description [String] - Optional payment description
  # @param originating_request [ItemRequest] - Optional item request that triggered this
  # @param order [Order] - Optional order associated with this payment
  # @return [TrustlineTransaction] - Durable write-buffer operation
  # @raise [ArgumentError] - If users are invalid or insufficient credit
  def process_payment!(amount, from_user, to_user, description: nil, originating_request: nil, order: nil, force_capacity: false, operation: "payment")
    raise ArgumentError, "Invalid users for this trustline" unless involves_users?(from_user, to_user)
    raise ArgumentError, "Insufficient credit" unless force_capacity || can_handle_payment?(amount, from_user)

    transaction do
      # Calculate new balance based on payment direction
      if from_user.id == user_a_id
        # A is paying B, increase current_balance (A owes more)
        new_balance = current_balance + amount
      else
        # B is paying A, decrease current_balance (A owes less)
        new_balance = current_balance - amount
      end

      # Create transaction record for audit trail. foaf_direction='sent'
      # means the FOAF transfer goes in the same direction as the Rails
      # initiator (from_user → to_user). The replay worker keys off this
      # to pick publish_payment vs publish_settlement on retry.
      tx_row = trustline_transactions.create!(
        amount: amount,
        description: description || "Payment from #{from_user.user_name} to #{to_user.user_name}",
        originating_request: originating_request,
        order: order,
        transaction_type: 'payment',
        initiated_by: from_user,
        balance_after: new_balance,
        foaf_direction: 'sent'
      )

      # Update balance and activity timestamp atomically
      update!(
        current_balance: new_balance,
        last_activity: Time.current
      )

      # Publish to FOAF. Writes foaf_operation_id + foaf_posted_at onto
      # tx_row on success. If FOAF is down the row sits with foaf_posted_at
      # nil — Foaf::ReplayWorker replays it when FOAF recovers.
      Foaf::LedgerHooks.after_payment(self, amount, from_user, to_user,
                                       description: description, order: order,
                                       operation: operation, tx_row: tx_row)

      tx_row.reload
    end
  end

  # Settles debt FROM `from_user` TO `to_user`. Inverse of process_payment!:
  # from_user's debt to to_user *decreases* by amount (and can swing past zero
  # into to_user owing from_user, bounded by the reverse credit limit).
  #
  # This is what the Pay button does — bruce hits Pay, bob confirms, bruce's
  # debt to bob goes down. Conventional pay semantics, requires recipient
  # confirmation (handled by PendingPayment#confirm!).
  def settle_payment!(amount, from_user, to_user, description: nil, order: nil, operation: "settlement", path_info: nil)
    raise ArgumentError, "Invalid users for this trustline" unless involves_users?(from_user, to_user)
    raise ArgumentError, "Amount must be positive" unless amount.to_f > 0

    transaction do
      if from_user.id == user_a_id
        # A is settling toward B: A's debt to B decreases (or B becomes A's debtor)
        new_balance = current_balance - amount
      else
        # B is settling toward A: B's debt to A decreases (or A becomes B's debtor)
        new_balance = current_balance + amount
      end

      # foaf_direction='received' marks this as a settlement-shape row. On
      # replay the worker picks publish_settlement (which sends a reverse-
      # direction FOAF transfer to reduce the initiator's debt).
      tx_row = trustline_transactions.create!(
        amount: amount,
        description: description || "Settlement from #{from_user.user_name} to #{to_user.user_name}",
        order: order,
        path_info: path_info,
        transaction_type: 'payment',
        initiated_by: from_user,
        balance_after: new_balance,
        foaf_direction: 'received'
      )

      update!(
        current_balance: new_balance,
        last_activity: Time.current
      )

      # Settlement gets its own ledger hook — the publisher auto-expands the
      # swapped sender's credit room before the transfer (FOAF doesn't have
      # a native settle primitive yet).
      Foaf::LedgerHooks.after_settlement(self, amount, from_user, to_user,
                                          description: description, order: order,
                                          metadata: path_info,
                                          operation: operation, tx_row: tx_row)

      tx_row.reload
    end
  end

  # Checks if this trustline involves the specified two users
  # @param user1 [User] - First user to check
  # @param user2 [User] - Second user to check
  # @return [Boolean] - Whether both users are part of this trustline
  def involves_users?(user1, user2)
    user_ids = [user1.id, user2.id].sort
    user_ids == [user_a_id, user_b_id]
  end
  
  # === CLASS METHODS FOR TRUSTLINE MANAGEMENT ===
  
  # Finds existing trustline or creates new one between two users
  # Automatically handles user ordering to prevent duplicate relationships
  # @param user1 [User] - First user
  # @param user2 [User] - Second user  
  # @param credit_limit_1_to_2 [Numeric] - Credit limit from user1 to user2
  # @param credit_limit_2_to_1 [Numeric] - Credit limit from user2 to user1
  # @return [Trustline] - The found or created trustline
  def self.find_or_create_between(user1, user2, credit_limit_1_to_2: 0, credit_limit_2_to_1: 0)
    user_a_id, user_b_id = [user1.id, user2.id].sort
    
    find_or_create_by(user_a_id: user_a_id, user_b_id: user_b_id) do |trustline|
      # Handle credit limits based on actual user order vs requested order
      if user1.id == user_a_id
        trustline.credit_limit_a_to_b = credit_limit_1_to_2
        trustline.credit_limit_b_to_a = credit_limit_2_to_1
      else
        trustline.credit_limit_a_to_b = credit_limit_2_to_1
        trustline.credit_limit_b_to_a = credit_limit_1_to_2
      end
    end
  end
  
  # === PAYMENT ROUTING METHODS FOR MULTI-HOP PAYMENTS ===
  
  # Finds a payment path between two users through the trustline network
  # Uses breadth-first search to find shortest path that can handle the amount
  # @param from_user [User] - Starting user
  # @param to_user [User] - Destination user
  # @param amount [Numeric] - Payment amount to route
  # @param max_hops [Integer] - Maximum number of hops allowed (default: 5)
  # @return [Array<User>, nil] - Array of users in path, or nil if no path found
  def self.find_payment_path(from_user, to_user, amount, max_hops: 5)
    return nil if from_user == to_user
    
    # Breadth-first search for shortest viable path
    queue = [[from_user]]
    visited = Set.new([from_user.id])
    
    while queue.any? && queue.first.length <= max_hops
      current_path = queue.shift
      current_user = current_path.last
      
      # Find all active trustlines for current user
      trustlines = Trustline.active.for_user(current_user)
      
      trustlines.each do |trustline|
        next_user = trustline.other_user(current_user)
        # Skip if this hop can't handle the payment amount
        next unless trustline.can_handle_payment?(amount, current_user)
        # Skip if we've already visited this user (prevent cycles)
        next if visited.include?(next_user.id)
        
        new_path = current_path + [next_user]
        
        # Found target - return the complete path
        return new_path if next_user == to_user
        
        # Add to queue for further exploration
        queue << new_path
        visited << next_user.id
      end
    end
    
    nil # No viable path found within constraints
  end
  
  # Executes a multi-hop payment along a predetermined path
  # All payments are processed atomically - if any fails, all are rolled back
  # @param path [Array<User>] - Array of users representing the payment path
  # @param amount [Numeric] - Payment amount
  # @param description [String] - Payment description
  # @param originating_request [ItemRequest] - Optional item request
  # @return [Boolean] - Success status
  # @raise [StandardError] - If path is invalid or any payment fails
  def self.execute_payment_path(path, amount, description: nil, originating_request: nil, order: nil)
    raise ArgumentError, "Path must have at least 2 users" if path.length < 2
    
    transaction do
      # Process payment for each consecutive pair in the path
      path.each_cons(2) do |from_user, to_user|
        trustline = Trustline.between_users(from_user, to_user).first
        raise "No trustline found between #{from_user.user_name} and #{to_user.user_name}" unless trustline
        
        trustline.process_payment!(
          amount,
          from_user,
          to_user,
          description: description,
          originating_request: originating_request,
          order: order
        )
      end
    end
    
    true
  end
  
  private
  
  # === VALIDATION METHODS ===
  
  # Ensures users are different (can't create trustline with yourself)
  def different_users
    errors.add(:user_b, "cannot be the same as User A") if user_a_id == user_b_id
  end

  # Prevent trustlines between demo and non-demo users
  def demo_boundary
    return unless user_a && user_b
    if user_a.demo? != user_b.demo?
      errors.add(:base, 'Cannot create trustlines between demo and non-demo users')
    end
  end
  
  # Validates user ordering constraint (user_a_id must be less than user_b_id)
  # This prevents duplicate trustlines between the same pair of users
  def user_order_constraint
    errors.add(:user_a, "ID must be less than User B ID") if user_a_id && user_b_id && user_a_id >= user_b_id
  end
  
  # Ensures proper user ordering before creation
  # Automatically swaps users and credit limits if needed
  def ensure_user_order
    if user_a_id && user_b_id && user_a_id > user_b_id
      self.user_a_id, self.user_b_id = user_b_id, user_a_id
      self.credit_limit_a_to_b, self.credit_limit_b_to_a = credit_limit_b_to_a, credit_limit_a_to_b
    end
  end
  
  # Sets the establishment date when creating new trustlines
  def set_established_date
    self.established_date ||= Time.current
  end
end 
