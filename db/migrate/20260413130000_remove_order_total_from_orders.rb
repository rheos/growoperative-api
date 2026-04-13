class RemoveOrderTotalFromOrders < ActiveRecord::Migration[5.2]
  def change
    remove_column :orders, :order_total, :decimal
  end
end
