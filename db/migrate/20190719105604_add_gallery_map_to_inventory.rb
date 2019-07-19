class AddGalleryMapToInventory < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :gallery_map, :string, default: [].to_yaml
  end
end
