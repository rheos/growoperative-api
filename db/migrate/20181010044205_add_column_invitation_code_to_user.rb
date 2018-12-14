class AddColumnInvitationCodeToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :invitation_code, :string
  end
end
