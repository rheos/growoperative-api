class AddColumnPriceToCategory < ActiveRecord::Migration[5.2]
  def change
    add_column :categories, :price, :decimal, precision: 10
  end
end
