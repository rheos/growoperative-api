class CreateItems < ActiveRecord::Migration[5.2]
  def change
    create_table :items do |t|
      t.references :user, foreign_key: true
      t.integer :quantity
      t.string :unit_id
      t.references :category, foreign_key: true
      t.references :item_name, foreign_key: true
      t.string :name
      t.references :grade, foreign_key: true
      t.decimal :price
      t.datetime :date_available

      t.timestamps
    end
  end
end
