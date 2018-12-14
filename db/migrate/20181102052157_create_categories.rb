class CreateCategories < ActiveRecord::Migration[5.2]
  def change
    create_table :categories do |t|
      t.string :category_name
      t.integer :default_unit
      t.integer :default_consumer_unit
      t.decimal :default_node_price

      t.timestamps
    end
  end
end
