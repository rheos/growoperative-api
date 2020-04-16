class RenameItemRelatiohshipsToItemRelationships < ActiveRecord::Migration[5.2]
  def change
    rename_table :item_relatiohships, :item_relationships
  end
end
