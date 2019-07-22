class ReplaceOrders < ActiveRecord::Migration[5.2]
  def change
    drop_table :order_contents
    drop_table :orders

    create_table :orders do |t|
      t.string :user_id
      t.string :friend_id
      t.string :order_label
      t.decimal :order_total
      t.integer :order_status
      t.datetime :estimated_date
      t.datetime :shipped_on
      t.datetime :signed_on

      t.timestamps
    end
  end
end
