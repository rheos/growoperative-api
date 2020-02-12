class AddEstimatedTimeLocationNoteFieldsToOrdersTable < ActiveRecord::Migration[5.2]
  def change
    add_column :orders, :estimated_time, :time
    add_column :orders, :location, :string, null: false
    add_column :orders, :note, :text
  end
end
