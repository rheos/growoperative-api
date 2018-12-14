class AddColumnItemUnitIdToItem < ActiveRecord::Migration[5.2]
  def change
    add_reference :items, :item_unit, foreign_key: true
  end
end
