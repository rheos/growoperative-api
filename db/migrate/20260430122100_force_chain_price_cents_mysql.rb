class ForceChainPriceCentsMysql < ActiveRecord::Migration[5.2]
  def up
    execute 'ALTER TABLE item_requests MODIFY price DECIMAL(10,2)'
    execute 'ALTER TABLE inventories MODIFY price DECIMAL(10,2)'
  end

  def down
    execute 'ALTER TABLE item_requests MODIFY price DECIMAL(10,0)'
    execute 'ALTER TABLE inventories MODIFY price DECIMAL(10,0)'
  end
end
