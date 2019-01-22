class AddProducerToInventory < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :producer_id, :integer
  end
end
