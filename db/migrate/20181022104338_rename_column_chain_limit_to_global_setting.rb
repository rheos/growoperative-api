class RenameColumnChainLimitToGlobalSetting < ActiveRecord::Migration[5.2]
  def change
    rename_column :global_settings, :chain_limit, :value
  end
end
