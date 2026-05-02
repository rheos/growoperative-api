require 'rails_helper'

RSpec.describe Category, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'exposes a default unit and allowed units in display order' do
    pound = ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592)
    ounce = ItemUnit.create!(unit_name: 'ounces', item_symbol: 'oz', unit_type: :weight, equivalent: 28.3495)
    bunch = ItemUnit.create!(unit_name: 'bunch', item_symbol: 'bunch', unit_type: :discrete)
    category = Category.create!(category_name: 'Herbs', default_unit: bunch, kind: :produce)

    category.category_units.create!(item_unit: ounce, display_order: 2)
    category.category_units.create!(item_unit: bunch, display_order: 0)
    category.category_units.create!(item_unit: pound, display_order: 1)

    expect(category.default_unit).to eq(bunch)
    expect(category.allowed_units.reload.map(&:item_symbol)).to eq(%w[bunch lb oz])
  end

  it 'marks goods categories separately from produce categories' do
    category = Category.create!(category_name: 'Garden Equipment', kind: :goods)

    expect(category).to be_goods
  end

  it 'sorts picker categories with vegetables first and goods after produce' do
    Category.create!(category_name: 'Tools', kind: :goods)
    Category.create!(category_name: 'Tinctures', kind: :produce)
    Category.create!(category_name: 'Vegetables', kind: :produce)

    expect(Category.for_picker.map(&:category_name)).to eq(['Vegetables', 'Tinctures', 'Tools'])
  end
end
