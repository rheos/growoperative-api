require 'rails_helper'

RSpec.describe Inventory, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'includes variable-weight terms in the dashboard item payload' do
    seller = User.create!(user_name: 'madrone-seller', password: 'password123')
    pound = ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592)
    meat = Category.create!(category_name: 'Meat', default_unit: pound, kind: :produce)
    item = Item.create!(
      user: seller,
      category: meat,
      item_unit: pound,
      quantity: 1,
      name: 'Beef side',
      price: 10,
      pricing_basis: :per_weight,
      sale_unit_label: 'side',
      est_weight_min: 450,
      est_weight_max: 550,
      cut_yield_factor: 0.6,
      on_the_rail_available: true,
      on_the_rail_delta: 1.30
    )

    attributes = item.inventory.first.to_json(seller).fetch(:attributes)

    expect(attributes).to include(
      'pricing-basis' => 'per_weight',
      'sale-unit-label' => 'side',
      'est-weight-min' => BigDecimal('450.0'),
      'est-weight-max' => BigDecimal('550.0'),
      'cut-yield-factor' => BigDecimal('0.6'),
      'on-the-rail-available' => true,
      'on-the-rail-delta' => BigDecimal('1.3')
    )
  end
end
