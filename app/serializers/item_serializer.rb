class ItemSerializer < ActiveModel::Serializer
  attributes :id, :category_id, :name, :grade_id,
    :item_unit_id, :unit_name,
    :item_name_id, :date_available,
    :created_at, :organic

  def unit_name
    object.item_unit.unit_name
  end
end
