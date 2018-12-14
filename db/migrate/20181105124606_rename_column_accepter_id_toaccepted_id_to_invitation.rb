class RenameColumnAccepterIdToacceptedIdToInvitation < ActiveRecord::Migration[5.2]
  def change
    rename_column :invitations, :accepter_id, :accepted_id
  end
end
