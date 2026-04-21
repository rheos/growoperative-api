class AddKindToPendingPayments < ActiveRecord::Migration[5.2]
  def change
    add_column :pending_payments, :kind, :integer, default: 0, null: false
    add_column :pending_payments, :paid_at, :datetime
    add_index :pending_payments, :kind
  end
end
