class UpdateItemTables < ActiveRecord::Migration[5.2]
  def change
    remove_reference :item_requests, :item, foreign_key: true
    add_reference :item_requests, :inventory, foreign_key: true

    add_column :request_contracts, :inventory_id, :integer, :index => true
  end
end
