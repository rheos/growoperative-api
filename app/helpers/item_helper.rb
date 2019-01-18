module ItemHelper
  def get_relation_price(user_id, friend_id)
    # get relationship price first
    relation_price = UserRelationshipPrice.find_by(user_id: user_id, friend_id: friend_id)
    if (!relation_price.nil? && relation_price.price)
      return relation_price.price
    end

    # get default price
    return get_user_markup(user_id)
  end

  def get_user_markup(user_id)
    # get default price
    category_price = UserCategoryPrice.find_by(user_id: user_id)
    if !category_price.nil?
      return category_price.price
    elsif Category.first.default_node_price
      return Category.first.default_node_price
    else
      if @global_node_price.nil?
        @global_node_price = GlobalSetting.find_by(setting: "user_category_relationship_price") ? GlobalSetting.find_by(setting: "user_category_relationship_price").value : (ENV['user_category_relationship_price'] ? ENV['user_category_relationship_price'].to_f : 1)
      end
      
      return @global_node_price
    end
  end
    
end