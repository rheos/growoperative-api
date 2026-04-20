class CreateSubnetConfigs < ActiveRecord::Migration[5.2]
  def change
    create_table :subnet_configs do |t|
      t.bigint :subnet_id, null: false
      t.integer :version, null: false
      t.json :config, null: false
      t.bigint :changed_by_user_id
      t.datetime :created_at, null: false
    end

    add_index :subnet_configs, [:subnet_id, :version], unique: true
  end
end
