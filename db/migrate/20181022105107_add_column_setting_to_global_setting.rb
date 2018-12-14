class AddColumnSettingToGlobalSetting < ActiveRecord::Migration[5.2]
  def change
    add_column :global_settings, :setting, :string, default: ''
  end
end
