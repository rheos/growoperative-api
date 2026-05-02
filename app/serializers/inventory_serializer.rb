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
    return nil unless object.target_user_id
    User.find(object.target_user_id).display_name_for(current_user)
  end
end
