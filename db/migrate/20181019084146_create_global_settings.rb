class CreateGlobalSettings < ActiveRecord::Migration[5.2]
  def change
    create_table :global_settings do |t|
      t.integer :chain_limit, default: 3

      t.timestamps
    end
  end
end
