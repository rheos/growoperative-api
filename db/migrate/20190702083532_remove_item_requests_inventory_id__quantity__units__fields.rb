class RemoveItemRequestsInventoryIdQuantityUnitsFields < ActiveRecord::Migration[5.2]
  def up
    remove_column :item_requests, :inventory_id
    remove_column :item_requests, :quantity
    remove_column :item_requests, :units
  end

  def down
    add_column :item_requests, :inventory_id, :integer
    add_column :item_requests, :quantity, :decimal
    add_column :item_requests, :units, :string
  end
end
