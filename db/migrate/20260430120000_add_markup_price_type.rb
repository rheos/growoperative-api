class AddMarkupPriceType < ActiveRecord::Migration[5.2]
  # Adds the percent/flat dimension to per-user and per-relationship markups.
  # The network-wide default markup lives on SubnetConfig (see
  # SiteConfig::DEFAULTS — default_markup / default_markup_type), not here.
  def up
    add_column :user_relationship_prices, :price_type, :string, default: 'flat', null: false
    add_column :user_category_prices, :price_type, :string, default: 'flat', null: false
  end

  def down
    remove_column :user_category_prices, :price_type
    remove_column :user_relationship_prices, :price_type
  end
end
