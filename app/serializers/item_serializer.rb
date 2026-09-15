class ItemSerializer < ActiveModel::Serializer
  attributes :id, :category_id, :name, :grade_id,
    :item_unit_id, :unit_name,
    :item_name_id, :date_available,
    :created_at, :organic,
    :pricing_basis, :sale_unit_label,
    :est_weight_min, :est_weight_max,
    :cut_yield_factor, :on_the_rail_available, :on_the_rail_delta

  def unit_name
    object.item_unit.unit_name
  end
end
