class ChangeQuantityTypeToDecimalOnItemRequests < ActiveRecord::Migration[5.2]
  def change
     change_column :item_requests, :quantity, :decimal, precision: 10, scale: 5
  end
end
