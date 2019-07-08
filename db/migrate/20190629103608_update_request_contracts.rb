class UpdateRequestContracts < ActiveRecord::Migration[5.2]
  def up
    add_column :request_contracts, :steps, :integer, default: 0
    add_column :request_contracts, :current_step, :integer, default: 0
    add_column :request_contracts, :deleted_at, :datetime
    add_column :request_contracts, :deleted_by, :datetime
  end

  def down
    remove_column :request_contracts, :steps
    remove_column :request_contracts, :current_step
    remove_column :request_contracts, :deleted_at
    remove_column :request_contracts, :deleted_by
  end
end
