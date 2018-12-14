class OrderContent < ApplicationRecord
  belongs_to :order
  belongs_to :item_request
end
