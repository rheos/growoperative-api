class AddSubnetSeedConfigToInvitations < ActiveRecord::Migration[5.2]
  def change
    add_column :invitations, :subnet_seed_config, :json
  end
end
