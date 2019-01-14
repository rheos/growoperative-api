class RequestContract < ApplicationRecord
  belongs_to :user
  belongs_to :item
  has_many   :item_requests, dependent: :destroy
  
  enum status: [ :pending, :accepted, :cancelled ]
end
