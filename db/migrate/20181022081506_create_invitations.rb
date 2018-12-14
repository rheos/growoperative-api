class CreateInvitations < ActiveRecord::Migration[5.2]
  def change
    create_table :invitations do |t|
      t.string :invitation_code
      t.references :user, foreign_key: true
      t.integer :status
      t.string :label, default: ""

      t.timestamps
    end
  end
end
