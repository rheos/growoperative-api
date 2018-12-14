class AddColumnItemSumbolToItemUnit < ActiveRecord::Migration[5.2]
  def change
    add_column :item_units, :item_symbol, :string
  end
end
