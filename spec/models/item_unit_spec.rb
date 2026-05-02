require 'rails_helper'

RSpec.describe ItemUnit, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'classifies convertible weight units separately from discrete units' do
    pound = ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592)
    each = ItemUnit.create!(unit_name: 'each', item_symbol: 'each', unit_type: :discrete)

    expect(pound).to be_unit_type_weight
    expect(pound.equivalent).to eq(453.592)
    expect(each).to be_unit_type_discrete
    expect(each.equivalent).to be_nil
  end

  it 'keeps count and volume dimensions available for future seed-only additions' do
    expect(described_class.unit_types).to include(
      'weight' => 0,
      'count' => 1,
      'volume' => 2,
      'discrete' => 3
    )
  end
end
