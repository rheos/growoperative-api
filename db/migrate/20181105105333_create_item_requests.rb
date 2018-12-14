class CreateItemRequests < ActiveRecord::Migration[5.2]
  def change
    create_table :item_requests do |t|
      t.references :user, foreign_key: true
      t.references :item, foreign_key: true
      t.integer "quantity"
      t.string "units"
      t.decimal "price", precision: 10
      t.integer "status"

      t.timestamps
    end
  end
end
