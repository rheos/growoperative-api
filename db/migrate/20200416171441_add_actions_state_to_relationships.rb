class AddActionsStateToRelationships < ActiveRecord::Migration[5.2]
  def change
    add_column :relationships, :actions_state, :integer, default: 0
  end
end
