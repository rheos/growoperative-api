# Table structure
#   bigint  => user_id
#   integer => friend_id
#   bigint  => category_id
#   bigint  => relationship_id
#   decimal => price, precision: 10
#   string  => price_type
#   decimal => receiving_price, precision: 10
#   string  => receiving_price_type
#-------------------------------
class UserRelationshipPrice < ApplicationRecord
  MARKUP_TYPES = %w[flat percent].freeze

  belongs_to :user
  belongs_to :friend, class_name: 'User'
  belongs_to :category
  belongs_to :relationship

  validates :price_type, inclusion: { in: MARKUP_TYPES }
end
