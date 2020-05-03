class CategorySize < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :category
  belongs_to :item_unit

  def as_json
    {
      id: id,
      category: category,
      item_unit_id: item_unit_id,
      unit: self.item_unit,
      quantity: quantity,
      price: price,
      user_id: user_id
    }
  end
end
