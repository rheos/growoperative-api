require 'rails_helper'

RSpec.describe Inventory, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'derives canonical quantity from the item unit' do
    user = User.create!(user_name: 'producer', password: 'password123')
    unit = ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592)
    category = Category.create!(category_name: 'Vegetables', default_unit: unit, kind: :produce)
    item = Item.create!(user: user, category: category, item_unit: unit, quantity: 2, name: 'Carrots', price: 4)

    inventory = item.inventory.first

    expect(inventory.quantity_canonical.to_f).to be_within(0.001).of(907.184)
    expect(inventory.canonical_unit_type).to eq('weight')
  end
end
