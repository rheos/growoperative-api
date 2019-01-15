class AddProducerIdtoItem < ActiveRecord::Migration[5.2]
  def change
    add_column :items, :producer_id, :integer, index: true
  end
end
