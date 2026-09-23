class SeedMeatCategory < ActiveRecord::Migration[7.1]
  # `db:seed` is not run by deployed app containers. The initial Meat row was
  # therefore absent from already-provisioned demo and beta databases despite
  # being present in db/seeds.rb. This idempotent data migration brings every
  # database that applies the feature schema to the same category catalog.
  def up
    # find_by! here assumed the unit catalog was already seeded, which is true of
    # every deployed database but false of a fresh one — so this migration
    # aborted the whole `db:migrate` run on a new checkout and in CI. Create the
    # pound if it is missing, with the same attributes db/seeds.rb uses.
    pound = ItemUnit.find_or_create_by!(item_symbol: 'lb') do |unit|
      unit.unit_name = 'pounds'
      unit.unit_type = :weight
      unit.equivalent = 453.592
    end
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
