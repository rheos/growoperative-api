class AddCancellationReasonToItemRequests < ActiveRecord::Migration[5.2]
  def change
    add_column :item_requests, :cancellation_reason, :text
  end
end
