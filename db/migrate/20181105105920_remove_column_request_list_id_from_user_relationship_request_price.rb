class RemoveColumnRequestListIdFromUserRelationshipRequestPrice < ActiveRecord::Migration[5.2]
  def change
    remove_column :user_relationship_request_prices, :request_list_id
  end
end
