class CreateRequestContracts < ActiveRecord::Migration[5.2]
  def change
    create_table :request_contracts do |t|
      t.references :user, foreign_key: true
      t.references :item, foreign_key: true
      t.decimal :quantity
      t.decimal :price
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
