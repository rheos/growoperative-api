class CreateItemRelatiohships < ActiveRecord::Migration[5.2]
  def change
    create_table :item_relatiohships do |t|
      t.references :item, foreign_key: true
      t.references :relationship, foreign_key: true
      t.boolean :status

      t.timestamps
    end
  end
end
