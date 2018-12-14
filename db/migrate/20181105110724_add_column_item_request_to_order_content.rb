class AddColumnItemRequestToOrderContent < ActiveRecord::Migration[5.2]
  def change
    add_reference :order_contents, :item_request, foreign_key: true
  end
end
