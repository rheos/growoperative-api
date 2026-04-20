class CreateSubnetMemberships < ActiveRecord::Migration[5.2]
  def change
    create_table :subnet_memberships do |t|
      t.bigint :user_id, null: false
      t.bigint :subnet_id, null: false
      t.bigint :joined_via_invitation_id
      t.boolean :is_primary, null: false, default: false
      t.datetime :created_at, null: false
    end

    add_index :subnet_memberships, [:user_id, :subnet_id], unique: true
    add_index :subnet_memberships, :subnet_id
    add_index :subnet_memberships, :joined_via_invitation_id
  end
end
