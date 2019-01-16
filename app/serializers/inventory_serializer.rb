class InventorySerializer < ActiveModel::Serializer
  attributes :id, :user_id, :quantity, :price, :total_price, 
    :item_id, :item,
    :target_user_id, :target_user_name,
    :action_request

  def item
    sr = ItemSerializer.new(object.item)
    sr.as_json
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
