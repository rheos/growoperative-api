# Create Trustline Transactions Table - Transaction History and Audit Trail
#
# This migration creates the trustline_transactions table that records all
# credit movements through the mutual credit network for complete audit trail.
#
# Table Structure:
# - trustline_id: Reference to the trustline this transaction affects
# - amount: Transaction amount (always positive, direction determined by context)
# - description: Human-readable description of the transaction
# - originating_request_id: Optional link to ItemRequest that triggered this
# - order_id: Optional link to Order associated with this transaction
# - path_info: JSON data for multi-hop payment routing information
# - transaction_type: Type of transaction (payment, settlement, adjustment, reversal)
# - initiated_by_id: User who initiated this transaction
# - balance_after: Trustline balance after this transaction was processed
# - is_reversed: Whether this transaction has been reversed/cancelled
#
# Transaction Types:
# - payment: Regular payment between users
# - settlement: External settlement (outside the app)
# - adjustment: Manual balance correction by admin
# - reversal: Reversal of a previous transaction
#
# Audit Trail:
# - Every balance change creates a transaction record
# - Reversals create new transactions rather than deleting originals
# - Balance reconstruction possible from transaction history

class CreateTrustlineTransactions < ActiveRecord::Migration[5.2]
  def change
    create_table :trustline_transactions do |t|
      # === CORE TRANSACTION DATA ===
      t.references :trustline, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.text :description
      
      # === RELATED ENTITIES ===
      # Optional references to business objects that triggered this transaction
      t.references :originating_request, null: true, foreign_key: { to_table: :item_requests }
      t.references :order, null: true, foreign_key: true
      
      # === PAYMENT ROUTING ===
      t.json :path_info  # For multi-hop payment routing information
      
      # === TRANSACTION METADATA ===
      t.string :transaction_type, null: false  # 'payment', 'settlement', 'adjustment', 'reversal'
      t.references :initiated_by, null: false, foreign_key: { to_table: :users }
      t.decimal :balance_after, precision: 10, scale: 2  # Trustline balance after this transaction
      t.boolean :is_reversed, default: false  # For marking reversed/cancelled transactions
      t.timestamps
      
      # === INDEXES FOR PERFORMANCE ===
      # Performance indexes (reference indexes are automatically created)
      t.index :transaction_type
      t.index :created_at
      t.index :is_reversed
    end
  end
end
