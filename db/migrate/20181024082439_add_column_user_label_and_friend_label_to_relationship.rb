class AddColumnUserLabelAndFriendLabelToRelationship < ActiveRecord::Migration[5.2]
  def change
    add_column :relationships, :user_label, :string
    add_column :relationships, :friend_label, :string
  end
end
