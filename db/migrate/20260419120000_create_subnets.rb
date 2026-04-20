class CreateSubnets < ActiveRecord::Migration[5.2]
  def change
    create_table :subnets do |t|
      t.bigint :seed_user_id, null: false
      t.string :slug, null: false
      t.string :name, null: false
      t.timestamps
    end

    add_index :subnets, :slug, unique: true
    add_index :subnets, :seed_user_id
  end
end
