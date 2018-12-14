class ChangePriceTypeOnUserRelationshipPrices < ActiveRecord::Migration[5.2]
  def change
    change_column :user_relationship_prices, :price, :decimal, precision: 10, scale: 2
    change_column :user_relationship_prices, :receiving_price, :decimal, precision: 10, scale: 2
  end
end
