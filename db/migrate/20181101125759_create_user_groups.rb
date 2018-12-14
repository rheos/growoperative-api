class CreateUserGroups < ActiveRecord::Migration[5.2]
  def change
    create_table :user_groups do |t|
      t.references :user, foreign_key: true
      t.integer :group_label

      t.timestamps
    end
  end
end
