class AddColumnItemRequestToRequestListRelationshipStatus < ActiveRecord::Migration[5.2]
  def change
    add_reference :request_list_relationship_statuses, :item_request, foreign_key: true
  end
end
