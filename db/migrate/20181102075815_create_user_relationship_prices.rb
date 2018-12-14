class CreateUserRelationshipPrices < ActiveRecord::Migration[5.2]
  def change
    create_table :user_relationship_prices do |t|
      t.references :user, foreign_key: true
      t.integer :friend_id
      t.references :category, foreign_key: true
      t.references :relationship, foreign_key: true
      t.decimal :price
      t.decimal :receiving_price
      t.string :receiving_price_type

      t.timestamps
    end
  end
end
