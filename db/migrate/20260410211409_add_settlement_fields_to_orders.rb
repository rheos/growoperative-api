class AddSettlementFieldsToOrders < ActiveRecord::Migration[5.2]
  def change
    add_column :orders, :settlement_type, :string
    add_column :orders, :settlement_status, :string
    add_column :orders, :settlement_proposed_by, :integer
  end
end
