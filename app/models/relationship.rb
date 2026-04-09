class Relationship < ApplicationRecord
  # It handle status value as enum
  enum status: [ :pending, :accepted, :declined, :blocked ]
  belongs_to :user
  belongs_to :friend, class_name: 'User'
  has_many   :item_relationships, dependent: :destroy
  has_many   :user_relationship_prices, dependent: :destroy
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses, dependent: :destroy

  validate :demo_boundary

  private

  # Prevent relationships between demo and non-demo users
  def demo_boundary
    return unless user && friend
    if user.demo? != friend.demo?
      errors.add(:base, 'Cannot create relationships between demo and non-demo users')
    end
  end

  # scope :excludeConsumers, -> (user_id, friend_id=nil) {
  #   if friend_id
  #     relations = Relationship.where("user_id = #{user_id} || friend_id=#{user_id}")
  #   else
  #   end
  # }
end
