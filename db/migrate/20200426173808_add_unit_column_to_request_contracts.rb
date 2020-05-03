class AddUnitColumnToRequestContracts < ActiveRecord::Migration[5.2]
  def change
    add_column :request_contracts, :unit, :string
  end
end
