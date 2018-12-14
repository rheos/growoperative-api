class CreateItemNames < ActiveRecord::Migration[5.2]
  def change
    create_table :item_names do |t|
      t.string :name
      t.references :category, foreign_key: true
      t.text :description

      t.timestamps
    end
  end
end
