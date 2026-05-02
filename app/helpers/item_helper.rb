module ItemHelper
  def get_relation_price(user_id, friend_id)
    if user_id == friend_id
      return Markup.flat(0)
    end
    # get relationship price first
    relation_price = UserRelationshipPrice.find_by(user_id: user_id, friend_id: friend_id)
    if (!relation_price.nil? && relation_price.price)
      return Markup.from_record(relation_price)
    end

    # get default price
    return get_user_markup(user_id)
  end

  def get_user_markup(user_id)
    category_price = UserCategoryPrice.find_by(user_id: user_id)
    return Markup.from_record(category_price) if category_price

    config = subnet_config_for(user_id)
    return Markup.new(type: config[:default_markup_type], value: config[:default_markup]) if config

    Markup.flat(Category.first&.default_node_price || 0)
  end

  def subnet_config_for(user_id)
    @subnet_config_cache ||= {}
    @subnet_config_cache[user_id] ||= SiteConfig.for(User.find_by(id: user_id)&.primary_subnet)
  end

  def apply_markup_chain(base_price, markups)
    markups.reduce(base_price.to_f) { |price, markup| markup.apply_to(price) }
  end

  def chain_prices(base_price, markups)
    prices = []
    markups.reduce(base_price.to_f) do |price, markup|
      next_price = markup.apply_to(price)
      prices << next_price
      next_price
    end
    prices
  end

  def target_user_name(user_id, target_user_id)
    User.find(target_user_id).display_name_for(User.find_by(id: user_id))
  end
    
end
