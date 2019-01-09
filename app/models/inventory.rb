class Inventory < ApplicationRecord
  belongs_to :user
  belongs_to :item
  belongs_to :item_request, optional: true

  enum status: [ :available, :reserved, :in_order ]
end
