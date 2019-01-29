class AddSignToRequestContract < ActiveRecord::Migration[5.2]
  def change
    add_column :request_contracts, :signed, :integer, :default => 0, :null => false, :limit => 1
  end
end
