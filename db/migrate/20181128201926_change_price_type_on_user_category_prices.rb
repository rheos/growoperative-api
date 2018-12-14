class ChangePriceTypeOnUserCategoryPrices < ActiveRecord::Migration[5.2]
  def change
    change_column :user_category_prices, :price, :decimal, precision: 10, scale: 2
  end
end
