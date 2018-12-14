class Review < ApplicationRecord
  belongs_to :user
  belongs_to :item_name
  belongs_to :item
end
