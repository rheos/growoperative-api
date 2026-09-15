class SeedMeatCategory < ActiveRecord::Migration[7.1]
  # `db:seed` is not run by deployed app containers. The initial Meat row was
  # therefore absent from already-provisioned demo and beta databases despite
  # being present in db/seeds.rb. This idempotent data migration brings every
  # database that applies the feature schema to the same category catalog.
  def up
    pound = ItemUnit.find_by!(item_symbol: 'lb')
    category = Category.find_or_initialize_by(category_name: 'Meat')
    category.assign_attributes(
      default_unit: pound,
      default_node_price: 1.0,
      kind: :produce
    )
    category.save!

    category_unit = CategoryUnit.find_or_initialize_by(category: category, item_unit: pound)
    category_unit.display_order = 0
    category_unit.save!
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Meat categories may have listings; remove them only through an explicit data operation.'
  end
end
