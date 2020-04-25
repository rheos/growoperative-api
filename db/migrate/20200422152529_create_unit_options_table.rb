class CreateUnitOptionsTable < ActiveRecord::Migration[5.2]
  def change
    create_table :unit_options do |t|
      t.integer :inventory_id, null: false
      t.integer :item_unit_id, null: false
      t.float :price
      t.float :quantity
      t.timestamps
    end
  end
end
