class CreateRequestLists < ActiveRecord::Migration[5.2]
  def change
    create_table :request_lists do |t|
      t.references :user, foreign_key: true
      t.references :item, foreign_key: true
      t.integer :quantity
      t.string :units
      t.decimal :price
      t.integer :staus

      t.timestamps
    end
  end
end
