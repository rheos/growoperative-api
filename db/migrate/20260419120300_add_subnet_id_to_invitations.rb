class AddSubnetIdToInvitations < ActiveRecord::Migration[5.2]
  def change
    add_column :invitations, :subnet_id, :bigint
    add_index :invitations, :subnet_id
  end
end
