class CategoryUnit < ApplicationRecord
  belongs_to :category
  belongs_to :item_unit

  validates :category_id, uniqueness: { scope: :item_unit_id }
end
