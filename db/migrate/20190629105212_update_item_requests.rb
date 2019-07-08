class UpdateItemRequests < ActiveRecord::Migration[5.2]
  def up
    add_column :item_requests, :step, :integer, default: 0
    add_column :item_requests, :accepted_at, :datetime
    add_column :item_requests, :shipped_at, :datetime
    add_column :item_requests, :signed_at, :datetime
  end

  def down
    remove_column :item_requests, :step
    remove_column :item_requests, :accepted_at
    remove_column :item_requests, :shipped_at
    remove_column :item_requests, :signed_at
  end
end
