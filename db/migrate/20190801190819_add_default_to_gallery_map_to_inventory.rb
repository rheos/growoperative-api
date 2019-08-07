class AddDefaultToGalleryMapToInventory < ActiveRecord::Migration[5.2]
  def change
    change_column :inventories, :gallery_map, :string, default: ["<-", "<-", "<-", "<-", "<-"].to_yaml
  end
end
