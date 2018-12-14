class DropTableRequestList < ActiveRecord::Migration[5.2]
  def change
    drop_table :request_lists
  end
end
