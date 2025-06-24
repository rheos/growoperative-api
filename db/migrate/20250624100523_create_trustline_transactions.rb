class CreateTrustlineTransactions < ActiveRecord::Migration[5.2]
  def change
    create_table :trustline_transactions do |t|
      t.references :trustline, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.text :description
      t.references :originating_request, null: true, foreign_key: { to_table: :item_requests }
      t.references :order, null: true, foreign_key: true
      t.json :path_info  # For multi-hop payment routing information
      t.string :transaction_type, null: false  # 'credit', 'debit', 'settlement', 'adjustment'
      t.references :initiated_by, null: false, foreign_key: { to_table: :users }
      t.decimal :balance_after, precision: 10, scale: 2  # Trustline balance after this transaction
      t.boolean :is_reversed, default: false  # For marking reversed/cancelled transactions
      t.timestamps
      
      # Performance indexes (reference indexes are automatically created)
      t.index :transaction_type
      t.index :created_at
      t.index :is_reversed
    end
  end
end
