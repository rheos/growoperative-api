class Relationship < ApplicationRecord
  # It handle status value as enum
  enum status: [ :pending, :accepted, :declined, :blocked ]
  belongs_to :user
  belongs_to :friend, class_name: 'User'
  has_many   :item_relationships, dependent: :destroy
  has_many   :user_relationship_prices, dependent: :destroy
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses, dependent: :destroy
end
