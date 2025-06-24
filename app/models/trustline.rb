class Trustline < ApplicationRecord
  belongs_to :user_a, class_name: 'User'
  belongs_to :user_b, class_name: 'User'
  has_many :trustline_transactions, dependent: :destroy
  
  validates :credit_limit_a_to_b, :credit_limit_b_to_a, :current_balance, 
            presence: true, numericality: true
  validates :user_a_id, uniqueness: { scope: :user_b_id }
  validate :different_users
  validate :user_order_constraint
  
  scope :active, -> { where(is_active: true) }
  scope :for_user, ->(user) { where("user_a_id = ? OR user_b_id = ?", user.id, user.id) }
  scope :between_users, ->(user1, user2) do
    user_a_id, user_b_id = [user1.id, user2.id].sort
    where(user_a_id: user_a_id, user_b_id: user_b_id)
  end
  
  before_validation :ensure_user_order, on: :create
  before_create :set_established_date
  
  # Core mutual credit methods
  
  def other_user(current_user)
    return user_b if current_user.id == user_a_id
    return user_a if current_user.id == user_b_id
    raise ArgumentError, "User #{current_user.id} is not part of this trustline"
  end
  
  def credit_limit_for(user)
    return credit_limit_a_to_b if user.id == user_a_id
    return credit_limit_b_to_a if user.id == user_b_id
    raise ArgumentError, "User #{user.id} is not part of this trustline"
  end
  
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
  
  def balance_for(user)
    if user.id == user_a_id
      current_balance  # Positive = A owes B, Negative = B owes A
    elsif user.id == user_b_id
      -current_balance # From B's perspective, flip the sign
    else
      raise ArgumentError, "User #{user.id} is not part of this trustline"
    end
  end
  
  def can_handle_payment?(amount, from_user)
    return false unless is_active?
    available_credit_for(from_user) >= amount
  end
  
  def process_payment!(amount, from_user, to_user, description: nil, originating_request: nil, order: nil)
    raise ArgumentError, "Invalid users for this trustline" unless involves_users?(from_user, to_user)
    raise ArgumentError, "Insufficient credit" unless can_handle_payment?(amount, from_user)
    
    transaction do
      # Calculate new balance
      if from_user.id == user_a_id
        # A is paying B, increase current_balance (A owes more)
        new_balance = current_balance + amount
      else
        # B is paying A, decrease current_balance (A owes less)
        new_balance = current_balance - amount
      end
      
      # Create transaction record
      trustline_transactions.create!(
        amount: amount,
        description: description || "Payment from #{from_user.user_name} to #{to_user.user_name}",
        originating_request: originating_request,
        order: order,
        transaction_type: 'payment',
        initiated_by: from_user,
        balance_after: new_balance
      )
      
      # Update balance and activity timestamp
      update!(
        current_balance: new_balance,
        last_activity: Time.current
      )
      
      new_balance
    end
  end
  
  def involves_users?(user1, user2)
    user_ids = [user1.id, user2.id].sort
    user_ids == [user_a_id, user_b_id]
  end
  
  def self.find_or_create_between(user1, user2, credit_limit_1_to_2: 0, credit_limit_2_to_1: 0)
    user_a_id, user_b_id = [user1.id, user2.id].sort
    
    find_or_create_by(user_a_id: user_a_id, user_b_id: user_b_id) do |trustline|
      if user1.id == user_a_id
        trustline.credit_limit_a_to_b = credit_limit_1_to_2
        trustline.credit_limit_b_to_a = credit_limit_2_to_1
      else
        trustline.credit_limit_a_to_b = credit_limit_2_to_1
        trustline.credit_limit_b_to_a = credit_limit_1_to_2
      end
    end
  end
  
  # Payment routing methods for multi-hop payments
  
  def self.find_payment_path(from_user, to_user, amount, max_hops: 5)
    return nil if from_user == to_user
    
    # Simple breadth-first search for now
    queue = [[from_user]]
    visited = Set.new([from_user.id])
    
    while queue.any? && queue.first.length <= max_hops
      current_path = queue.shift
      current_user = current_path.last
      
      # Find all trustlines for current user
      trustlines = Trustline.active.for_user(current_user)
      
      trustlines.each do |trustline|
        next_user = trustline.other_user(current_user)
        next unless trustline.can_handle_payment?(amount, current_user)
        next if visited.include?(next_user.id)
        
        new_path = current_path + [next_user]
        
        # Found target
        return new_path if next_user == to_user
        
        # Add to queue for further exploration
        queue << new_path
        visited << next_user.id
      end
    end
    
    nil # No path found
  end
  
  def self.execute_payment_path(path, amount, description: nil, originating_request: nil)
    raise ArgumentError, "Path must have at least 2 users" if path.length < 2
    
    transaction do
      path.each_cons(2) do |from_user, to_user|
        trustline = Trustline.between_users(from_user, to_user).first
        raise "No trustline found between #{from_user.user_name} and #{to_user.user_name}" unless trustline
        
        trustline.process_payment!(
          amount, 
          from_user, 
          to_user, 
          description: description,
          originating_request: originating_request
        )
      end
    end
    
    true
  end
  
  private
  
  def different_users
    errors.add(:user_b, "cannot be the same as User A") if user_a_id == user_b_id
  end
  
  def user_order_constraint
    errors.add(:user_a, "ID must be less than User B ID") if user_a_id && user_b_id && user_a_id >= user_b_id
  end
  
  def ensure_user_order
    if user_a_id && user_b_id && user_a_id > user_b_id
      self.user_a_id, self.user_b_id = user_b_id, user_a_id
      self.credit_limit_a_to_b, self.credit_limit_b_to_a = credit_limit_b_to_a, credit_limit_a_to_b
    end
  end
  
  def set_established_date
    self.established_date ||= Time.current
  end
end 