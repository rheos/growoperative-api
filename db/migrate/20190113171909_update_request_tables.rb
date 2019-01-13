class UpdateRequestTables < ActiveRecord::Migration[5.2]
  def change
    add_reference :item_requests, :request_contract, foreign_key: true
    remove_reference :inventories, :item_request, foreign_key: true
    add_column :inventories, :ref_id, :integer
  end
end
