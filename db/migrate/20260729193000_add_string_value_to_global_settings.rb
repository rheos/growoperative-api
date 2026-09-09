class AddStringValueToGlobalSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :global_settings, :string_value, :text
  end
end
