class BackfillUnitsAndPricingCategories < ActiveRecord::Migration[5.2]
  class MigrationItemUnit < ActiveRecord::Base
    self.table_name = 'item_units'
    self.inheritance_column = :_type_disabled
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = 'categories'
  end

  class MigrationCategoryUnit < ActiveRecord::Base
    self.table_name = 'category_units'
  end

  PRODUCE = 0
  GOODS = 1

  CATEGORY_CONFIGS = [
    { name: 'Vegetables', default: 'lb', units: %w[lb oz kg g each bunch], kind: PRODUCE, price: 1.0 },
    { name: 'Fruit', default: 'lb', units: %w[lb oz kg g each], kind: PRODUCE, price: 1.0 },
    { name: 'Herbs and Greens', default: 'bunch', units: %w[bunch head lb oz g each], kind: PRODUCE, price: 1.0 },
    { name: 'Herbs', default: 'bunch', units: %w[bunch oz g each], kind: PRODUCE, price: 1.0 },
    { name: 'Eggs', default: 'dozen', units: %w[dozen half-dozen each], kind: PRODUCE, price: 1.0 },
    { name: 'Plant Starts', default: 'each', units: %w[each 6-pack], kind: PRODUCE, price: 1.0 },
    { name: 'Honey & Preserves', default: 'jar', units: %w[jar oz lb], kind: PRODUCE, price: 1.0 },
    { name: 'Hot Sauce / Bottled', default: 'bottle', units: %w[bottle], kind: PRODUCE, price: 1.0 },
    { name: 'Tinctures', default: 'bottle', units: %w[bottle oz g], kind: PRODUCE, price: 1.0 },
    { name: 'Garden Equipment', default: 'each', units: %w[each dozen], kind: GOODS, price: 1.0 },
    { name: 'Tools', default: 'each', units: %w[each dozen], kind: GOODS, price: 1.0 },
    { name: 'Containers & Packaging', default: 'each', units: %w[each dozen case], kind: GOODS, price: 1.0 },
    { name: 'Seeds & Inputs', default: 'packet', units: %w[packet oz g lb], kind: GOODS, price: 1.0 },
    { name: 'Books & Media', default: 'each', units: %w[each dozen], kind: GOODS, price: 1.0 },
    { name: 'Other / Miscellaneous', default: 'each', units: %w[each lb dozen], kind: GOODS, price: 1.0 }
  ].freeze

  def up
    normalize_existing_category_names!
    CATEGORY_CONFIGS.each { |config| upsert_category!(config) }
  end

  def down
    # Data backfill only. Keep categories and unit mappings so existing items remain valid.
  end

  private

  def normalize_existing_category_names!
    rename_category!('herbs and greens', 'Herbs and Greens')
    rename_category!('tinctures', 'Tinctures')
  end

  def rename_category!(old_name, new_name)
    old_category = MigrationCategory.find_by(category_name: old_name)
    return unless old_category

    existing_new_category = MigrationCategory.find_by(category_name: new_name)
    if existing_new_category && existing_new_category.id != old_category.id
      execute("UPDATE items SET category_id = #{existing_new_category.id} WHERE category_id = #{old_category.id}")
      execute("UPDATE item_names SET category_id = #{existing_new_category.id} WHERE category_id = #{old_category.id}")
      execute("UPDATE user_category_prices SET category_id = #{existing_new_category.id} WHERE category_id = #{old_category.id}")
      execute("UPDATE user_relationship_prices SET category_id = #{existing_new_category.id} WHERE category_id = #{old_category.id}")
      execute("UPDATE category_sizes SET category_id = #{existing_new_category.id} WHERE category_id = #{old_category.id}")
      execute("DELETE FROM category_units WHERE category_id = #{old_category.id}")
      old_category.destroy!
    else
      old_category.update!(category_name: new_name)
    end
  end

  def upsert_category!(config)
    default_unit = unit_by_symbol!(config[:default])
    category = MigrationCategory.find_or_initialize_by(category_name: config[:name])
    category.default_unit_id = default_unit.id
    category.default_node_price = config[:price]
    category.kind = config[:kind]
    category.save!

    config[:units].each_with_index do |symbol, index|
      unit = unit_by_symbol!(symbol)
      category_unit = MigrationCategoryUnit.find_or_initialize_by(category_id: category.id, item_unit_id: unit.id)
      category_unit.display_order = index
      category_unit.save!
    end
  end

  def unit_by_symbol!(symbol)
    MigrationItemUnit.find_by!(item_symbol: symbol)
  end
end
