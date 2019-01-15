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
  has_many   :item_requests, dependent: :destroy
  has_many   :user_category_prices, dependent: :destroy
  has_many   :user_relationship_prices, dependent: :destroy
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :reviews, dependent: :destroy
  # has_many   :relations, class_name: 'Relationship', :foreign_key => 'friend_id'

  attr_accessor :current_password
  # enum user_type: [:consumer, :producer, :broker, :retailer, :wholesaler, :admin]
  # call_backs
  before_create :set_parent
  after_create :update_invitiation_limit, :set_depth, :set_invitation_limit, :set_relationship
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

  def has_role?(role)
    if self.user_groups.pluck(:group_label).include?(role)
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
      Relationship.create(user_id: self.parent_id, friend_id: self.id, status: 1, action_user_id:self.parent_id, user_label: @invitation.label, friend_label: @invitation.note_label)
    end
  end
  def find_invitation
    @invitation = Invitation.find_by(invitation_code: self.invited_code)
  end
end
