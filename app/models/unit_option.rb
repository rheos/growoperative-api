class UnitOption < ApplicationRecord
  belongs_to :inventory
  belongs_to :item_unit

  def convert (target_name)
    
  end

  def to_json
    {
      id: id,
      quantity: quantity,
      price: price,
      unit: self.item_unit.unit_name
    }
  end
end
