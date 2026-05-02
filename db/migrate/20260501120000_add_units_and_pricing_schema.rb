class AddUnitsAndPricingSchema < ActiveRecord::Migration[5.2]
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

  class MigrationItem < ActiveRecord::Base
    self.table_name = 'items'
    belongs_to :item_unit, class_name: 'AddUnitsAndPricingSchema::MigrationItemUnit', optional: true
  end

  class MigrationInventory < ActiveRecord::Base
    self.table_name = 'inventories'
    belongs_to :item, class_name: 'AddUnitsAndPricingSchema::MigrationItem', optional: true
  end

  class MigrationUnitOption < ActiveRecord::Base
    self.table_name = 'unit_options'
    belongs_to :item_unit, class_name: 'AddUnitsAndPricingSchema::MigrationItemUnit', optional: true
  end

  WEIGHT = 0
  COUNT = 1
  VOLUME = 2
  DISCRETE = 3

  def up
    add_column :item_units, :unit_type, :integer, null: false, default: WEIGHT
    remove_column :item_units, :type, :integer

    reconcile_item_units!

    add_reference :categories, :default_unit, foreign_key: { to_table: :item_units }, null: true
    add_column :categories, :kind, :integer, null: false, default: 0

    create_table :category_units do |t|
      t.references :category, null: false, foreign_key: true
      t.references :item_unit, null: false, foreign_key: true
      t.integer :display_order, null: false, default: 0
      t.timestamps
    end
    add_index :category_units, [:category_id, :item_unit_id], unique: true

    backfill_category_defaults!

    remove_column :categories, :default_unit, :integer
    remove_column :categories, :default_consumer_unit, :integer

    add_column :inventories, :quantity_canonical, :decimal, precision: 14, scale: 4
    add_column :inventories, :canonical_unit_type, :integer
    backfill_inventory_canonical!
    change_column_null :inventories, :quantity_canonical, false

    add_column :unit_options, :quantity_canonical, :decimal, precision: 14, scale: 4
    add_column :unit_options, :canonical_unit_type, :integer
    add_column :unit_options, :label, :string
    backfill_unit_option_canonical!

    add_column :items, :pack_contains_quantity, :decimal, precision: 14, scale: 4
    add_reference :items, :pack_contains_unit, foreign_key: { to_table: :item_units }, null: true
    add_column :items, :condition, :integer
    add_column :items, :one_time_listing, :boolean, null: false, default: false
  end

  def down
    add_column :categories, :default_unit, :integer
    add_column :categories, :default_consumer_unit, :integer

    remove_column :items, :one_time_listing, :boolean
    remove_column :items, :condition, :integer
    remove_reference :items, :pack_contains_unit, foreign_key: { to_table: :item_units }
    remove_column :items, :pack_contains_quantity, :decimal

    remove_column :unit_options, :label, :string
    remove_column :unit_options, :canonical_unit_type, :integer
    remove_column :unit_options, :quantity_canonical, :decimal

    remove_column :inventories, :canonical_unit_type, :integer
    remove_column :inventories, :quantity_canonical, :decimal

    drop_table :category_units
    remove_column :categories, :kind, :integer
    remove_reference :categories, :default_unit, foreign_key: { to_table: :item_units }

    add_column :item_units, :type, :integer
    remove_column :item_units, :unit_type, :integer
  end

  private

  def reconcile_item_units!
    upsert_unit('pounds', 'lb', WEIGHT, 453.592, id: 1, aliases: ['lbs'])
    upsert_unit('ounces', 'oz', WEIGHT, 28.3495, id: 2)
    reconcile_boxes_unit!
    upsert_unit('bottle', 'bottle', DISCRETE, nil, id: 4, aliases: ['bottles'])
    upsert_unit('grams', 'g', WEIGHT, 1, id: 5)

    delete_or_repurpose_blank_unit!

    upsert_unit('kilograms', 'kg', WEIGHT, 1000)
    upsert_unit('each', 'each', DISCRETE, nil)
    upsert_unit('dozen', 'dozen', DISCRETE, nil)
    upsert_unit('half-dozen', 'half-dozen', DISCRETE, nil)
    upsert_unit('6-pack', '6-pack', DISCRETE, nil)
    upsert_unit('bunch', 'bunch', DISCRETE, nil)
    upsert_unit('head', 'head', DISCRETE, nil)
    upsert_unit('jar', 'jar', DISCRETE, nil)
    upsert_unit('case', 'case', DISCRETE, nil)
    upsert_unit('packet', 'packet', DISCRETE, nil)
  end

  def upsert_unit(unit_name, item_symbol, unit_type, equivalent, id: nil, aliases: [])
    scope = MigrationItemUnit.where(item_symbol: [item_symbol, *aliases])
    scope = scope.or(MigrationItemUnit.where(id: id)) if id
    unit = scope.first || MigrationItemUnit.new
    unit.unit_name = unit_name
    unit.item_symbol = item_symbol
    unit.unit_type = unit_type
    unit.equivalent = equivalent
    unit.save!
    unit
  end

  def reconcile_boxes_unit!
    box = MigrationItemUnit.find_by(id: 3) || MigrationItemUnit.find_by(item_symbol: 'box')
    return unless box

    if referenced_unit?(box.id)
      box.update!(unit_name: 'case', item_symbol: 'case', unit_type: DISCRETE, equivalent: nil)
    else
      box.destroy!
    end
  end

  def delete_or_repurpose_blank_unit!
    blank = MigrationItemUnit.where(unit_name: [nil, ''], item_symbol: [nil, '']).first
    return unless blank

    if referenced_unit?(blank.id)
      blank.update!(unit_name: 'each', item_symbol: 'each', unit_type: DISCRETE, equivalent: nil)
    else
      blank.destroy!
    end
  end

  def referenced_unit?(unit_id)
    select_value("SELECT COUNT(*) FROM items WHERE item_unit_id = #{unit_id}").to_i.positive? ||
      select_value("SELECT COUNT(*) FROM unit_options WHERE item_unit_id = #{unit_id}").to_i.positive? ||
      select_value("SELECT COUNT(*) FROM category_sizes WHERE item_unit_id = #{unit_id}").to_i.positive?
  end

  def backfill_category_defaults!
    pound = unit_by_symbol('lb')
    MigrationCategory.update_all(default_unit_id: pound&.id)
  end

  def backfill_inventory_canonical!
    MigrationInventory.includes(item: :item_unit).find_each do |inventory|
      quantity_canonical, canonical_unit_type = canonical_values(inventory.quantity, inventory.item&.item_unit)
      inventory.update_columns(
        quantity_canonical: quantity_canonical,
        canonical_unit_type: canonical_unit_type
      )
    end
  end

  def backfill_unit_option_canonical!
    MigrationUnitOption.includes(:item_unit).find_each do |unit_option|
      quantity_canonical, canonical_unit_type = canonical_values(unit_option.quantity, unit_option.item_unit)
      unit_option.update_columns(
        quantity_canonical: quantity_canonical,
        canonical_unit_type: canonical_unit_type
      )
    end
  end

  def canonical_values(quantity, unit)
    return [0, WEIGHT] if quantity.nil?

    unit_type = unit&.unit_type || WEIGHT
    equivalent = unit&.equivalent
    canonical_quantity =
      if unit_type == WEIGHT && equivalent.present?
        BigDecimal(quantity.to_s) * BigDecimal(equivalent.to_s)
      else
        BigDecimal(quantity.to_s)
      end

    [canonical_quantity, unit_type]
  end

  def unit_by_symbol(symbol)
    MigrationItemUnit.find_by(item_symbol: symbol)
  end
end
