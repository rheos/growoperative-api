class CreateCategorySizesTable < ActiveRecord::Migration[5.2]
  def change
    create_table :category_sizes do |t|
      t.integer :user_id
      t.integer :category_id, null: false
      t.integer :item_unit_id, null: false
      t.float :quantity
      t.float :price
    end
  end
end
