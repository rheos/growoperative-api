class AddFoafWriteResolutionToTrustlineTransactions < ActiveRecord::Migration[6.0]
  def change
    add_column :trustline_transactions, :foaf_pending_transfer_id, :bigint
    add_column :trustline_transactions, :foaf_write_state, :string
    add_column :trustline_transactions, :foaf_write_error, :text

    add_index :trustline_transactions, :foaf_pending_transfer_id
    add_index :trustline_transactions, :foaf_write_state
  end
end
