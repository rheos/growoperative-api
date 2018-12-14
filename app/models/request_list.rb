class RequestList < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :user_relationship_request_prices, dependent: :destroy
  has_many   :request_list_relationship_statuses,dependent: :destroy
  has_many   :order_contents, dependent: :destroy
  enum status: [ :pending, :accepted ]
end
