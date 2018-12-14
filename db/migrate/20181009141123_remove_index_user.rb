class RemoveIndexUser < ActiveRecord::Migration[5.2]
  def change
    remove_index :users, ["uid", "provider"]
  end
end
