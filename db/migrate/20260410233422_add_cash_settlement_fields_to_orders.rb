class AddCashSettlementFieldsToOrders < ActiveRecord::Migration[5.2]
  def change
    add_column :orders, :settlement_counter_type, :string
    add_column :orders, :settlement_counter_by, :integer
    add_column :orders, :cash_amount, :decimal, precision: 10, scale: 2
    add_column :orders, :cash_paid_by, :integer
    add_column :orders, :cash_confirmed_by, :integer
  end
end
