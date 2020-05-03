# frozen_string_literal: true

class User < ApplicationRecord
	# Include default devise modules. Others available are:
	# :confirmable, :lockable, :timeoutable and :omniauthable

	devise :database_authenticatable, :registerable,
				 :recoverable, :rememberable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: JWTBlacklist, authentication_keys: [:user_name]
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
  # has_many   :relations, class_name: 'Relationship', :foreign_key => 'friend_id'

  attr_accessor :current_password
  # enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  # call_backs
  before_create :set_parent
  after_create :update_invitiation_limit, :set_depth, :set_invitation_limit, :set_relationship, :set_category_sizes

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
    if self.user_groups.pluck(:group_label).include?("admin")
      true
    else
      false
    end
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

  # This method will get remaining invitation count of user
  def ramaining_invitation_limit
    self.invite_limit - self.invitations.count
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
end
