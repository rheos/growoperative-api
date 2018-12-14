class AddColumnItemRequestToUserRelationshipRequestPrice < ActiveRecord::Migration[5.2]
  def change
    add_reference :user_relationship_request_prices, :item_request, foreign_key: true
  end
end
