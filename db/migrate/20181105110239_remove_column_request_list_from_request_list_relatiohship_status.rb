class RemoveColumnRequestListFromRequestListRelatiohshipStatus < ActiveRecord::Migration[5.2]
  def change
    remove_column :request_list_relationship_statuses, :request_list_id
  end
end
