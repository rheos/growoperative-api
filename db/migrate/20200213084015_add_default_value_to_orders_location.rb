class AddDefaultValueToOrdersLocation < ActiveRecord::Migration[5.2]
  def change
    change_column :orders, :location, :string, null: false, default: 'pick up'
  end
end
