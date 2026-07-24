class CreateIntroductions < ActiveRecord::Migration[5.2]
  def change
    unless table_exists?(:introductions)
      create_table :introductions do |t|
        t.bigint   :introducer_id,   null: false
        t.bigint   :introducee_a_id, null: false
        t.bigint   :introducee_b_id, null: false
        t.integer  :status,          null: false, default: 0
        t.datetime :accepted_a_at,   null: true
        t.datetime :accepted_b_at,   null: true
        t.integer  :declined_by_id,  null: true
        t.timestamps
      end
    end

    # No unique index — a row lock (introduction.with_lock) covers the dual-accept
    # race; see Technical Risks in the spec.
    unless index_exists?(:introductions, [:introducer_id, :status], name: 'index_introductions_on_introducer_and_status')
      add_index :introductions, [:introducer_id, :status], name: 'index_introductions_on_introducer_and_status'
    end
    add_index :introductions, :introducee_a_id, name: 'index_introductions_on_introducee_a_id' unless index_exists?(:introductions, :introducee_a_id, name: 'index_introductions_on_introducee_a_id')
    add_index :introductions, :introducee_b_id, name: 'index_introductions_on_introducee_b_id' unless index_exists?(:introductions, :introducee_b_id, name: 'index_introductions_on_introducee_b_id')

    add_foreign_key :introductions, :users, column: :introducer_id unless foreign_key_exists?(:introductions, :users, column: :introducer_id)
    add_foreign_key :introductions, :users, column: :introducee_a_id unless foreign_key_exists?(:introductions, :users, column: :introducee_a_id)
    add_foreign_key :introductions, :users, column: :introducee_b_id unless foreign_key_exists?(:introductions, :users, column: :introducee_b_id)
  end
end
