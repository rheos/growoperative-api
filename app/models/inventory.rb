class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :item_request, optional: true
  has_many   :item_requests, dependent: :destroy

  enum status: [ :unavailable, :available, :reserved, :in_order ]

  attr_accessor :target_user_id
  attr_accessor :total_price
  attr_accessor :action_request
end
