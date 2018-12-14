class ChangeQuantityTypeOnItems < ActiveRecord::Migration[5.2]
  def change
    change_column :items, :quantity, :decimal, precision: 10, scale: 5
  end
end
