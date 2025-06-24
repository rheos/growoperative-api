class CreateTrustlines < ActiveRecord::Migration[5.2]
  def change
    create_table :trustlines do |t|
      t.references :user_a, null: false, foreign_key: { to_table: :users }
      t.references :user_b, null: false, foreign_key: { to_table: :users }
      t.decimal :credit_limit_a_to_b, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :credit_limit_b_to_a, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :current_balance, precision: 10, scale: 2, default: 0.0, null: false
      t.boolean :is_active, default: true, null: false
      t.datetime :established_date, null: false
      t.datetime :last_activity
      t.text :notes  # For agreement terms or notes
      t.timestamps
      
      # Ensure unique trustlines (no duplicates between same users)
      t.index [:user_a_id, :user_b_id], unique: true, name: 'index_trustlines_on_user_pair'
      
      # Performance indexes (user_a_id and user_b_id indexes are automatically created by references)
      t.index :is_active
      t.index :established_date
    end
  end
end
