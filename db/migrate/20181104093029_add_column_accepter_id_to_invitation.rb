class AddColumnAccepterIdToInvitation < ActiveRecord::Migration[5.2]
  def change
    add_column :invitations, :accepter_id, :integer
  end
end
