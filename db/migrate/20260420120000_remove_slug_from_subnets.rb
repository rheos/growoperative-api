class RemoveSlugFromSubnets < ActiveRecord::Migration[5.2]
  def change
    remove_index :subnets, :slug
    remove_column :subnets, :slug, :string
  end
end
