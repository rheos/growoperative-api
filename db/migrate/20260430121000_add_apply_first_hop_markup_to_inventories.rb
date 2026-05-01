class AddApplyFirstHopMarkupToInventories < ActiveRecord::Migration[5.2]
  def change
    add_column :inventories, :apply_first_hop_markup, :boolean, default: false, null: false
  end
end
