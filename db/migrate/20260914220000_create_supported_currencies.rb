class CreateSupportedCurrencies < ActiveRecord::Migration[7.1]
  def change
    create_table :supported_currencies do |t|
      t.string :code, null: false, limit: 3
      t.string :name, null: false
      t.string :locale, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :supported_currencies, :code, unique: true
  end
end
