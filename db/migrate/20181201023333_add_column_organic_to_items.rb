class AddColumnOrganicToItems < ActiveRecord::Migration[5.2]
  def change
    add_column :items, :organic, :boolean, default: 0
  end
end
