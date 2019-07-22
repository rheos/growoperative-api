class AddOrderIdToItemRequests < ActiveRecord::Migration[5.2]
  def change
    add_column :item_requests, :order_id, :integer
  end
end
