class AddColumnChainLimitAndInviteLimitToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :chain_limit, :integer, default: 0
    add_column :users, :invite_limit, :integer, default: 0
  end
end
