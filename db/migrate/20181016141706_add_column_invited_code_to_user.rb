class AddColumnInvitedCodeToUser < ActiveRecord::Migration[5.2]
  def change
    add_column :users, :invited_code, :string
  end
end
