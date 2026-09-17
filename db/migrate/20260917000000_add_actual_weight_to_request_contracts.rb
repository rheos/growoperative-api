class AddActualWeightToRequestContracts < ActiveRecord::Migration[7.1]
  # Increment 2 of variable-weight "buy a share" listings (meat).
  #
  # `quantity` on a request contract stays what it has always been: how many of
  # the thing was claimed. For a per_weight listing that is a count of SHARES
  # (one side, two quarters), which is what the inventory decrement operates on.
  # It is deliberately NOT repurposed to hold pounds — doing that would make
  # Inventory#decrement_for_request! subtract 500 from a stock of 4.
  #
  # Weight is therefore its own pair of columns:
  #   estimated_weight — total hanging weight expected across the claimed shares,
  #                      recorded at request/reserve time so the buyer's estimate
  #                      is preserved after the real number lands.
  #   actual_weight    — total hanging weight on the scale. Null until the seller
  #                      runs finalize_weight. Settlement bills on this.
  #
  # Both are null for per_unit lines, which keeps every fixed-price listing on
  # exactly the path it was on before.
  def change
    add_column :request_contracts, :estimated_weight, :decimal, precision: 10, scale: 2
    add_column :request_contracts, :actual_weight, :decimal, precision: 10, scale: 2
    add_column :request_contracts, :weight_finalized_at, :datetime
    add_column :request_contracts, :on_the_rail, :boolean, default: false, null: false
  end
end
