class AddDefaultChainLimitAndInvitationLimitToUser < ActiveRecord::Migration[5.2]
  def change
    change_column :users, :chain_limit, :integer, default: 3
    change_column :users, :invite_limit, :integer, default: 3
  end
end
