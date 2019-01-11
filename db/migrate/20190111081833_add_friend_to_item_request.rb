class AddFriendToItemRequest < ActiveRecord::Migration[5.2]
  def change
    add_column :item_requests, :friend_id, :integer
  end
end
