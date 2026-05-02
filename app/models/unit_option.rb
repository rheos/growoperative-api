class UnitOption < ApplicationRecord
  belongs_to :inventory
  belongs_to :item_unit

  before_validation :set_canonical_quantity

  enum canonical_unit_type: {
    weight: 0,
    count: 1,
    volume: 2,
    discrete: 3
  }, _prefix: :canonical

  def convert (target_name)
    
  end

  def to_json
    {
      id: id,
      quantity: quantity,
      price: price,
      unit: self.item_unit.unit_name,
      unit_data: self.item_unit
    }
  end

  private

  def set_canonical_quantity
    return if quantity.nil?

    self.canonical_unit_type = item_unit&.unit_type || :weight

    self.quantity_canonical =
      if canonical_weight? && item_unit&.equivalent.present?
        BigDecimal(quantity.to_s) * BigDecimal(item_unit.equivalent.to_s)
      else
        BigDecimal(quantity.to_s)
      end
  end
end
