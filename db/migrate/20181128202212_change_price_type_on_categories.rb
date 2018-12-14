class ChangePriceTypeOnCategories < ActiveRecord::Migration[5.2]
  def change
    change_column :categories, :default_node_price, :decimal, precision: 10, scale: 2
  end
end
