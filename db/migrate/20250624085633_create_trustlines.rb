# Create Trustlines Table - Mutual Credit System Foundation
#
# This migration creates the core trustlines table that stores bidirectional
# credit relationships between users in the mutual credit system.
#
# Table Structure:
# - user_a_id, user_b_id: The two users in the relationship (user_a_id < user_b_id)
# - credit_limit_a_to_b: Maximum credit user_a can extend to user_b
# - credit_limit_b_to_a: Maximum credit user_b can extend to user_a
# - current_balance: Net balance (positive = user_a owes user_b)
# - is_active: Whether the trustline is currently active
# - established_date: When the relationship was first created
# - last_activity: Last time a transaction occurred
# - notes: Free-form text for relationship terms or agreements
#
# Constraints:
# - Unique index on (user_a_id, user_b_id) prevents duplicate relationships
# - User ordering (user_a_id < user_b_id) prevents reverse duplicates
# - All monetary fields have precision 10, scale 2 for currency accuracy

class CreateTrustlines < ActiveRecord::Migration[5.2]
  def change
    create_table :trustlines do |t|
      # === USER RELATIONSHIP ===
      # Foreign keys to users table with proper constraints
      t.references :user_a, null: false, foreign_key: { to_table: :users }
      t.references :user_b, null: false, foreign_key: { to_table: :users }
      
      # === CREDIT LIMITS ===
      # Bidirectional credit limits with currency precision
      t.decimal :credit_limit_a_to_b, precision: 10, scale: 2, default: 0.0, null: false
      t.decimal :credit_limit_b_to_a, precision: 10, scale: 2, default: 0.0, null: false
      
      # === BALANCE TRACKING ===
      # Current net balance between users
      t.decimal :current_balance, precision: 10, scale: 2, default: 0.0, null: false
      
      # === STATUS AND METADATA ===
      t.boolean :is_active, default: true, null: false
      t.datetime :established_date, null: false
      t.datetime :last_activity
      t.text :notes  # For agreement terms or notes
      t.timestamps
      
      # === INDEXES FOR PERFORMANCE ===
      # Ensure unique trustlines (no duplicates between same users)
      t.index [:user_a_id, :user_b_id], unique: true, name: 'index_trustlines_on_user_pair'
      
      # Performance indexes (user_a_id and user_b_id indexes are automatically created by references)
      t.index :is_active
      t.index :established_date
    end
  end
end
