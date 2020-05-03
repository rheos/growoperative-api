class AddTypeAndEquivalentTiItemInits < ActiveRecord::Migration[5.2]
  def change
    add_column :item_units, :type, :integer, defauld: 0
    add_column :item_units, :equivalent, :float, defauld: 1
  end
end
