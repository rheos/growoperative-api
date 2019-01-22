module ItemHelper
  def get_relation_price(user_id, friend_id)
    if user_id == friend_id
      return 0
    end
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

  def target_user_name(user_id, target_user_id)
    relation = Relationship.where "user_id IN (?) AND friend_id IN (?)",
      [user_id, target_user_id], [user_id, target_user_id]
    if relation.first
      if (relation.first.user_id == user_id) && relation.first.friend_label.present?
        relation.first.friend_label
      elsif (relation.first.friend_id == user_id) && relation.first.user_label.present?
        relation.first.user_label
      elsif target_user_id
        user = User.find(target_user_id)
        user.nickname ? user.nickname : user.user_name
      end
    end
  end 
    
end