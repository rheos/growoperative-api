class AddDiscoveryLocationToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :latitude,            :decimal, precision: 9, scale: 6
    add_column :users, :longitude,           :decimal, precision: 9, scale: 6
    add_column :users, :location_opted_in,   :boolean, null: false, default: false
    add_column :users, :location_updated_at, :datetime
    add_column :users, :discovery_radius_km, :integer

    add_index :users, [:latitude, :longitude], name: 'index_users_on_latitude_and_longitude'
  end
end
