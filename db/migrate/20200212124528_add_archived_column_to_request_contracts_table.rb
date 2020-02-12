class AddArchivedColumnToRequestContractsTable < ActiveRecord::Migration[5.2]
  def change
    add_column :request_contracts, :archived, :boolean, default: false
  end
end
