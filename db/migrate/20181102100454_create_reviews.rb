class CreateReviews < ActiveRecord::Migration[5.2]
  def change
    create_table :reviews do |t|
      t.references :user, foreign_key: true
      t.references :item_name, foreign_key: true
      t.references :item, foreign_key: true
      t.integer :producer_id
      t.integer :value

      t.timestamps
    end
  end
end
