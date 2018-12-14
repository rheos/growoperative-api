class Order < ApplicationRecord
  belongs_to :relationship
  has_many   :order_contents, dependent: :destroy
end
