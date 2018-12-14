# Table structure
#   bigint  => user_id
#   integer => friend_id
#   bigint  => category_id
#   bigint  => relationship_id
#   decimal => price, precision: 10
#   decimal => receiving_price, precision: 10
#   string  => receiving_price_type
#-------------------------------
class UserRelationshipPrice < ApplicationRecord
  belongs_to :user
  belongs_to :friend, class_name: 'User'
  belongs_to :category
  belongs_to :relationship
end
