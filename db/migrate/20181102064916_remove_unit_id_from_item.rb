class RemoveUnitIdFromItem < ActiveRecord::Migration[5.2]
  def change
    remove_column :items, :unit_id
  end
end
