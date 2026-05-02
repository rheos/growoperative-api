class CategorySize < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :category
  belongs_to :item_unit

  before_validation :set_canonical_quantity

  enum canonical_unit_type: {
    weight: 0,
    count: 1,
    volume: 2,
    discrete: 3
  }, _prefix: :canonical

  def as_json
    {
      id: id,
      category: category,
      item_unit_id: item_unit_id,
      unit: self.item_unit,
      quantity: quantity,
      quantity_canonical: quantity_canonical,
      canonical_unit_type: canonical_unit_type,
      price: price,
      user_id: user_id
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
