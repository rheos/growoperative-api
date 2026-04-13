class CreatePendingPayments < ActiveRecord::Migration[5.2]
  def change
    create_table :pending_payments do |t|
      t.references :from_user, foreign_key: { to_table: :users }
      t.references :to_user, foreign_key: { to_table: :users }
      t.references :trustline, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.text :description
      t.integer :status, default: 0, null: false
      t.text :rejected_reason
      t.datetime :confirmed_at
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :pending_payments, :status
  end
end
