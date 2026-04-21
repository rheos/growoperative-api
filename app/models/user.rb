# frozen_string_literal: true

class User < ApplicationRecord
	# Include default devise modules. Others available are:
	# :confirmable, :lockable, :timeoutable and :omniauthable

	devise :database_authenticatable, :registerable,
				 :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: JWTBlacklist, authentication_keys: [:user_name]

	# Avatar upload (uses existing `image` column)
	mount_uploader :image, ImagesUploader

	# Validation
  validates :user_name, presence: :true, uniqueness: { case_sensitive: false }
  validates :invitations_count, numericality: { only_integer: true }
  # Association
  has_many   :sub_users, class_name: "User", foreign_key: "parent_id", dependent: :destroy
  has_many   :invitations, dependent: :destroy
  has_many   :relationships, dependent: :destroy
  has_many   :friends, through: :relationships, source: 'friend',:foreign_key => 'friend_id'
  has_many   :user_groups, dependent: :destroy
  has_many   :items, dependent: :destroy
  has_many   :inventories, dependent: :destroy
  has_many   :item_requests, dependent: :destroy
  has_many   :user_category_prices, dependent: :destroy
  has_many   :user_relationship_prices, dependent: :destroy
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :reviews, dependent: :destroy
  has_many   :category_sizes, dependent: :destroy
  has_many   :notifications, foreign_key: :recipient_id, dependent: :destroy
  has_many   :subnet_memberships, dependent: :destroy
  has_many   :subnets, through: :subnet_memberships
  # has_many   :relations, class_name: 'Relationship', :foreign_key => 'friend_id'
  
  # === MUTUAL CREDIT SYSTEM ASSOCIATIONS ===
  # Trustline relationships where this user is either user_a or user_b
  has_many   :trustlines_as_user_a, class_name: 'Trustline', foreign_key: 'user_a_id', dependent: :destroy
  has_many   :trustlines_as_user_b, class_name: 'Trustline', foreign_key: 'user_b_id', dependent: :destroy
  # Transactions initiated by this user
  has_many   :initiated_trustline_transactions, class_name: 'TrustlineTransaction', foreign_key: 'initiated_by_id', dependent: :destroy

  attr_accessor :current_password
  # enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]

  # Demo user support
  scope :demo, -> { joins(:user_groups).where(user_groups: { group_label: 'demo' }).distinct }

  def demo?
    user_groups.exists?(group_label: 'demo')
  end

  def superuser?
    user_groups.exists?(group_label: 'superuser')
  end

  # call_backs
  before_create :set_parent
  after_create :update_invitiation_limit, :set_depth, :set_invitation_limit, :set_relationship, :set_category_sizes, :inherit_demo_group, :join_subnet_from_invitation

  def set_category_sizes
    CategorySize.where(user_id: nil).each do |c| 
      self.category_sizes.create(quantity: c.quantity, item_unit_id: c.item_unit_id, category_id: c.category_id)
    end
  end

	def email_required?
  	false
	end

  def ensure_invitation_token
    if invitation_token.blank?
      self.update invitation_token: generate_authentication_token
    end
  end

  def generate_authentication_token
    loop do
      token = Devise.friendly_token
      break token unless User.find_by(invitation_token: token)
    end
  end

  def is_admin?
    labels = self.user_groups.pluck(:group_label)
    labels.include?("admin") || labels.include?("superuser")
  end

  def is_superuser?
    self.user_groups.pluck(:group_label).include?("superuser")
  end

  def invited_by_name
    return nil if invited_code.blank?
    invitation = Invitation.find_by(invitation_code: invited_code)
    return nil unless invitation
    User.find_by(id: invitation.user_id)&.user_name
  end

  def is_producer?
    group_labels = self.user_groups.pluck(:group_label)
    if group_labels.size == 1 && group_labels.include?("producer")
      true
    else
      false
    end
  end

  def is_consumer?
    group_labels = self.user_groups.pluck(:group_label)
    if group_labels.size == 1 && group_labels.include?("consumer")
      true
    else
      false
    end
  end

  def has_role?(role)
    if self.user_groups.pluck(:group_label).include?(role)
      true
    else
      false
    end
  end

  def only_consumer_retailer?
    groups = self.user_groups.pluck(:group_label)
    if groups.length == 1 && (groups.include?('consumer') || groups.include?('retailer'))
      true
    else
      false
    end
  end

  # This method will use to set parent id
  def set_parent
    find_invitation
    parent = @invitation.try(:user)
    if parent
      self.parent_id = parent.id
    end
  end

  # This method set chain limit of invited User who register using another user invitation code
  def set_depth
    find_invitation
    unless self.is_admin?
      user = @invitation.try(:user)
      if user
        self.update depth: user.depth + 1
      end
    end
  end

  # This method set invitation limit of User who register using another user invitation code
  def set_invitation_limit
    find_invitation
    user = @invitation.try(:user)
    if user
      unless user.is_admin?
        self.update invite_limit: user.invite_limit
      end
    end
  end

  # This method will update inviation limit of user whoes inivitation code is used
  def update_invitiation_limit
    find_invitation
    user = @invitation.try(:user)
    if user
      @invitation.update(status: 1, accepted_id:self.id)
      # This will generate user_group for register user
      self.user_groups.create(group_label: @invitation.user_type)
      # self.update user_type: @invitation.user_type
      user.update invitations_count: user.invitations_count+1
    end
  end

  # Remaining invitation slots available to this user. Only *pending* (i.e.
  # unused) invitations count against the limit — once someone accepts a code,
  # that slot frees up. Historically this counted all invitations including
  # accepted ones, which meant a user who'd successfully onboarded N people
  # could never generate another code.
  def ramaining_invitation_limit
    self.invite_limit - self.invitations.pending.count
  end

  # This method build relationship between user
  def set_relationship
    find_invitation
    if self.invited_code
      relation = Relationship.create(user_id: self.parent_id, friend_id: self.id, status: 1, action_user_id:self.parent_id, user_label: @invitation.label, friend_label: @invitation.note_label)
      UserRelationshipPrice.create(price: @invitation.user_price, category_id: 1, relationship_id: relation.id, friend_id: self.id, user_id: self.parent_id) if @invitation.user_price
    end
  end
  def find_invitation
    @invitation = Invitation.find_by(invitation_code: self.invited_code)
  end

  # If the inviting user is a demo user, the new user inherits the demo group
  def inherit_demo_group
    parent = User.find_by(id: parent_id)
    if parent&.demo?
      user_groups.find_or_create_by!(group_label: 'demo')
    end
  end

  # Subnet membership helper — at most one primary per user.
  def primary_subnet
    subnet_memberships.primary.first&.subnet
  end

  # Creates a primary SubnetMembership for the new user from the invitation's
  # subnet. Nullable subnet_id on the invitation is intentional during the
  # backfill window (see plan 17) — we silently no-op and leave the user
  # without a membership until Phase 3 backfill runs.
  def join_subnet_from_invitation
    find_invitation
    return unless @invitation&.subnet_id
    subnet_memberships.create!(
      subnet_id: @invitation.subnet_id,
      joined_via_invitation_id: @invitation.id,
      is_primary: true
    )
  end
  
  # === MUTUAL CREDIT SYSTEM METHODS ===
  
  # Returns all trustlines associated with this user (both as user_a and user_b)
  # @return [ActiveRecord::Relation] - All trustlines for this user
  def trustlines
    Trustline.for_user(self)
  end
  
  # Returns only active trustlines for this user
  # @return [ActiveRecord::Relation] - Active trustlines only
  def active_trustlines
    trustlines.active
  end
  
  # Finds the trustline between this user and another user
  # @param other_user [User] - The other user in the relationship
  # @return [Trustline, nil] - The trustline or nil if none exists
  def trustline_with(other_user)
    Trustline.between_users(self, other_user).first
  end
  
  # Calculates total amount this user owes to others
  # @return [BigDecimal] - Total amount owed (positive balances)
  def total_credit_owed
    # Sum of positive balances (what I owe others)
    trustlines.sum do |trustline|
      balance = trustline.balance_for(self)
      balance > 0 ? balance : 0
    end
  end
  
  # Calculates total amount owed to this user by others
  # @return [BigDecimal] - Total amount owed to user (negative balances)
  def total_credit_owed_to_me
    # Sum of negative balances (what others owe me)
    trustlines.sum do |trustline|
      balance = trustline.balance_for(self)
      balance < 0 ? balance.abs : 0
    end
  end
  
  # Calculates net credit position (positive = creditor, negative = debtor)
  # @return [BigDecimal] - Net position in the network
  def net_credit_position
    # Positive = more is owed to me, Negative = I owe more
    total_credit_owed_to_me - total_credit_owed
  end
  
  # Calculates total available credit across all active trustlines
  # @return [BigDecimal] - Total credit available for spending
  def available_credit_total
    # Total credit I can still use across all trustlines
    trustlines.active.sum { |trustline| trustline.available_credit_for(self) }
  end
  
  # Checks if user can make a payment of specified amount
  # @param amount [Numeric] - The payment amount to check
  # @param to_user [User, nil] - Specific target user, or nil to check total capacity
  # @return [Boolean] - Whether the payment is possible
  def can_pay?(amount, to_user = nil)
    return false if amount <= 0
    
    if to_user
      # Check direct trustline capacity
      trustline = trustline_with(to_user)
      return trustline&.can_handle_payment?(amount, self) || false
    else
      # Check total network capacity
      available_credit_total >= amount
    end
  end
  
  # Establishes a new trustline with another user or returns existing one
  # @param other_user [User] - The user to establish trustline with
  # @param my_credit_limit [Numeric] - Credit limit I extend to them
  # @param their_credit_limit [Numeric] - Credit limit they extend to me
  # @param notes [String] - Optional notes about the relationship
  # @return [Trustline, false] - The trustline or false if failed
  DEFAULT_CREDIT_LIMIT = 100
  def establish_trustline_with(other_user, my_credit_limit: nil, their_credit_limit: nil, notes: nil)
    return false if self == other_user
    return trustline_with(other_user) if trustline_with(other_user)

    # Default both sides to a sensible starting limit so a fresh trustline is
    # immediately usable. Counterparty can adjust their side later.
    my_limit = my_credit_limit.to_f.positive? ? my_credit_limit : DEFAULT_CREDIT_LIMIT
    their_limit = their_credit_limit.to_f.positive? ? their_credit_limit : DEFAULT_CREDIT_LIMIT

    Trustline.find_or_create_between(
      self,
      other_user,
      credit_limit_1_to_2: my_limit,
      credit_limit_2_to_1: their_limit
    ).tap do |trustline|
      trustline.update(notes: notes) if notes
    end
  end

  # Returns the avatar URL (thumbnail version if available)
  def avatar_url
    return nil unless image.present?
    image.thumb500.url
  end
end
