class AddAvatarsToInventory < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :avatars, :json
  end
end
