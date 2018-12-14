class RenameColumnChainLimitToUser < ActiveRecord::Migration[5.2]
  def change
    rename_column :users, :chain_limit, :depth
  end
end
