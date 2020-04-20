class AddFriendActionsStateToRelationships < ActiveRecord::Migration[5.2]
  def change
    add_column :relationships, :friend_actions_state, :integer, default: 0
  end
end
