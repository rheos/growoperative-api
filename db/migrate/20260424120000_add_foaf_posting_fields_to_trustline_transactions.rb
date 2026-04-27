class AddFoafPostingFieldsToTrustlineTransactions < ActiveRecord::Migration[5.2]
  def up
    add_column :trustline_transactions, :foaf_operation_id, :bigint
    add_column :trustline_transactions, :foaf_posted_at, :datetime
    add_column :trustline_transactions, :foaf_direction, :string, limit: 16

    # Existing rows were either already mirrored to FOAF (we just don't know
    # the op id) or predate shadow mode entirely. Either way the retry worker
    # must not replay them — mark them posted at their created_at.
    execute <<~SQL
      UPDATE trustline_transactions
      SET foaf_posted_at = created_at
      WHERE foaf_posted_at IS NULL
    SQL

    add_index :trustline_transactions, :foaf_posted_at
  end

  def down
    remove_index :trustline_transactions, :foaf_posted_at
    remove_column :trustline_transactions, :foaf_direction
    remove_column :trustline_transactions, :foaf_posted_at
    remove_column :trustline_transactions, :foaf_operation_id
  end
end
