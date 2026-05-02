class AddCanonicalFieldsToCategorySizes < ActiveRecord::Migration[5.2]
  class MigrationItemUnit < ActiveRecord::Base
    self.table_name = 'item_units'
  end

  class MigrationCategorySize < ActiveRecord::Base
    self.table_name = 'category_sizes'
    belongs_to :item_unit, class_name: 'AddCanonicalFieldsToCategorySizes::MigrationItemUnit'
  end

  def up
    add_column :category_sizes, :quantity_canonical, :decimal, precision: 14, scale: 4
    add_column :category_sizes, :canonical_unit_type, :integer

    MigrationCategorySize.includes(:item_unit).find_each do |category_size|
      unit = category_size.item_unit
      unit_type = unit&.unit_type || 0
      equivalent = unit&.equivalent
      quantity_canonical =
        if unit_type == 0 && equivalent.present?
          BigDecimal(category_size.quantity.to_s) * BigDecimal(equivalent.to_s)
        else
          BigDecimal(category_size.quantity.to_s)
        end

      category_size.update_columns(
        quantity_canonical: quantity_canonical,
        canonical_unit_type: unit_type
      )
    end
  end

  def down
    remove_column :category_sizes, :canonical_unit_type, :integer
    remove_column :category_sizes, :quantity_canonical, :decimal
  end
end
