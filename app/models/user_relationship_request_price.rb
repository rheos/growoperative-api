# Table structure
#    bigint  => user_id
#    integer => friend_id
#    bigint  => relationship_id
#    decimal => price, precision: 10
#    bigint  => item_request_id"
#-------------------------------------
class UserRelationshipRequestPrice < ApplicationRecord
  belongs_to :user
  belongs_to :friend, class_name: 'User'
  belongs_to :relationship
  belongs_to :item_request, optional: true
end
