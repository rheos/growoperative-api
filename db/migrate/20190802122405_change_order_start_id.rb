class ChangeOrderStartId < ActiveRecord::Migration[5.2]
  def change
    execute("ALTER TABLE orders AUTO_INCREMENT = 100110")
  end
end
