class AddRefPriceToInventories < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :ref_price, :float, default: nil
  end
end
