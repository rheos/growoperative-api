class CreateFoafOutboxEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :foaf_outbox_entries do |t|
      t.references :trustline, null: false, foreign_key: { on_delete: :cascade }
      t.string :operation_type, null: false, limit: 32
      t.json :payload, null: false
      t.string :foaf_write_state, null: false, default: "pending"
      t.text :foaf_write_error
      t.datetime :foaf_posted_at
      t.datetime :superseded_at
      t.timestamps
    end

    add_index :foaf_outbox_entries,
              [:operation_type, :foaf_posted_at, :superseded_at],
              name: "index_foaf_outbox_entries_for_replay"
    add_index :foaf_outbox_entries,
              [:trustline_id, :operation_type, :created_at],
              name: "index_foaf_outbox_entries_on_trustline_operation"
  end
end
