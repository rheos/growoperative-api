class AddColumnNoteLabelToInvitation < ActiveRecord::Migration[5.2]
  def change
    add_column :invitations, :note_label, :string
  end
end
