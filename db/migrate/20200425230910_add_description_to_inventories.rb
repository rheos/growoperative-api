class AddDescriptionToInventories < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :description, :text, null: true
  end
end
