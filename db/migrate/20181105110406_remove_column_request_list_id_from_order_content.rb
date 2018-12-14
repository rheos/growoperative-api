class RemoveColumnRequestListIdFromOrderContent < ActiveRecord::Migration[5.2]
  def change
    remove_column :order_contents, :request_list_id
  end
end
