class RemoveRequestContractPriceSigned < ActiveRecord::Migration[5.2]
  def up
    remove_column :request_contracts, :price
    remove_column :request_contracts, :signed
  end

  def down
    add_column :request_contracts, :price, :decimal
    add_column :request_contracts, :signed, :integer, null: false, default: 0
  end
end
