class AddCentsToChainPrices < ActiveRecord::Migration[5.2]
  def up
    change_column :item_requests, :price, :decimal, precision: 10, scale: 2
    change_column :inventories, :price, :decimal, precision: 10, scale: 2
  end

  def down
    change_column :item_requests, :price, :decimal, precision: 10
    change_column :inventories, :price, :decimal, precision: 10
  end
end
