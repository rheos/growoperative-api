class CreateOrders < ActiveRecord::Migration[5.2]
  def change
    create_table :orders do |t|
      t.references :relationship, foreign_key: true
      t.decimal :total
      t.string :status
      t.integer :paid

      t.timestamps
    end
  end
end
