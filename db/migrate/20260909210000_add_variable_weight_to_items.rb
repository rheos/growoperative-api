class AddVariableWeightToItems < ActiveRecord::Migration[7.1]
  # Variable-weight "buy a share" listings (meat): priced per pound of
  # carcass/hanging weight, sold as a side / quarter / whole with an estimate
  # range until the actual weight is recorded at finalize time (Increment 2).
  #
  # `pricing_basis` defaults to 0 (per_unit), so every existing listing is
  # unchanged — the fixed-price-per-unit path is untouched.
  def change
    add_column :items, :pricing_basis,        :integer, default: 0, null: false
    add_column :items, :sale_unit_label,      :string
    add_column :items, :est_weight_min,       :decimal, precision: 10, scale: 2
    add_column :items, :est_weight_max,       :decimal, precision: 10, scale: 2
    add_column :items, :cut_yield_factor,     :decimal, precision: 4,  scale: 3, default: 0.6
    add_column :items, :on_the_rail_available, :boolean, default: false, null: false
    add_column :items, :on_the_rail_delta,    :decimal, precision: 10, scale: 2, default: 0, null: false
  end
end
