class ChangeQuantityTypeToDecimalOnRequestContracts < ActiveRecord::Migration[5.2]
  def change
    change_column :request_contracts, :quantity, :decimal, precision: 10, scale: 5
  end
end
