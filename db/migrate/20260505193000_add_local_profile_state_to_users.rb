class AddLocalProfileStateToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :deleted_at, :datetime
    add_column :users, :disabled_at, :datetime

    add_index :users, :deleted_at
    add_index :users, :disabled_at
  end
end
