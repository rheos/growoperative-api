class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many :item_request, dependent: :destroy

  enum status: [ :unavailable, :available, :reserved, :in_order ]

  attr_accessor :target_user_id
  attr_accessor :total_price
  attr_accessor :action_request

  def target_user_name(current_user)
    relation = Relationship.where "user_id IN (?) AND friend_id IN (?)",
      [current_user.id, self.target_user_id], [current_user.id, self.target_user_id]
    if relation.first
      if (relation.first.user_id == current_user.id) && relation.first.friend_label.present?
        relation.first.friend_label
      elsif (relation.first.friend_id == current_user.id) && relation.first.user_label.present?
        relation.first.user_label
      elsif self.target_user_id
        user = User.find(self.target_user_id)
        user.nickname ? user.nickname : user.user_name
      end
    end
  end 
end
