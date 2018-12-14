class ItemSerializer < ActiveModel::Serializer
  attributes :id, :user_id, :quantity, :category_id, :name, :grade_id,
    :price, :item_unit_id, :item_name_id, :date_available, :unit_name,
    :created_at, :target_user_id, :target_user_name, :total_price, :organic

  def unit_name
    object.item_unit.unit_name
  end

  def target_user_name
    relation = Relationship.where "user_id IN (?) AND friend_id IN (?)",
      [current_user.id, object.target_user_id], [current_user.id, object.target_user_id]
    if relation.first
      if (relation.first.user_id == current_user.id) && relation.first.friend_label.present?
        relation.first.friend_label
      elsif (relation.first.friend_id == current_user.id) && relation.first.user_label.present?
        relation.first.user_label
      elsif object.target_user_id
        user = User.find(object.target_user_id)
        user.nickname ? user.nickname : user.user_name
      end
    end
  end 
end
