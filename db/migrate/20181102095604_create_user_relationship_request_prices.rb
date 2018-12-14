class CreateUserRelationshipRequestPrices < ActiveRecord::Migration[5.2]
  def change
    create_table :user_relationship_request_prices do |t|
      t.references :user, foreign_key: true
      t.integer :friend_id
      t.references :relationship, foreign_key: true
      t.references :request_list, foreign_key: true
      t.decimal :price

      t.timestamps
    end
  end
end
