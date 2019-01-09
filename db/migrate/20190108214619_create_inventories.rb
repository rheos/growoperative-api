class CreateInventories < ActiveRecord::Migration[5.2]
  def change
    create_table :inventories do |t|
      t.references :user, foreign_key: true
      t.references :item, foreign_key: true
      t.references :item_request, foreign_key: true
      t.float :quantity
      t.decimal :price
      t.integer :status
      t.timestamps
    end
  end
end
