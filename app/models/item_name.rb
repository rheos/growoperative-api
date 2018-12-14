class ItemName < ApplicationRecord
  belongs_to :category
  has_many   :items, dependent: :destroy
  has_many   :item_retationships, dependent: :destroy
  has_many   :reviews, dependent: :destroy
end
