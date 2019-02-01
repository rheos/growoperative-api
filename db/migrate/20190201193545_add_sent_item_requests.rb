class AddSentItemRequests < ActiveRecord::Migration[5.2]
  def change
    add_column :item_requests, :sent, :boolean, :default => 0, :null => false
  end
end
