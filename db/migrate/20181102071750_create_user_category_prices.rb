class CreateUserCategoryPrices < ActiveRecord::Migration[5.2]
  def change
    create_table :user_category_prices do |t|
      t.references :user, foreign_key: true
      t.references :category, foreign_key: true
      t.decimal :price
      t.string :unit

      t.timestamps
    end
  end
end
