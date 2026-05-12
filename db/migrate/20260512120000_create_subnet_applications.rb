class CreateSubnetApplications < ActiveRecord::Migration[5.2]
  def change
    create_table :subnet_applications do |t|
      t.string  :community_name, null: false
      t.string  :location,       null: false
      t.string  :contact_name,   null: false
      t.string  :contact_email,  null: false
      t.text    :description
      t.string  :status,         null: false, default: 'pending'
      t.bigint  :reviewed_by_user_id
      t.datetime :reviewed_at
      t.bigint  :created_subnet_id

      t.timestamps
    end

    add_index :subnet_applications, :status
    add_index :subnet_applications, :location
    add_index :subnet_applications, :created_at
  end
end
