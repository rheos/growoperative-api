# Add FOAF protocol identity columns to users.
# These are the custodial wallet keys — stored here, not in FOAF.
# The signing module is isolated and will be replaced with actual wallet signing later.

class AddFoafIdentityToUsers < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :foaf_address, :string, limit: 42
    add_column :users, :foaf_public_key, :text
    add_column :users, :foaf_private_key, :text  # encrypted in production
    add_column :users, :foaf_registered, :boolean, default: false

    add_index :users, :foaf_address, unique: true
  end
end
