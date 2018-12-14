class CreateOrderContents < ActiveRecord::Migration[5.2]
  def change
    create_table :order_contents do |t|
      t.references :order, foreign_key: true
      t.references :request_list, foreign_key: true
      t.string :status

      t.timestamps
    end
  end
end
