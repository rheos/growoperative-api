require 'rails_helper'

RSpec.describe CategorySize, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'stores canonical weight quantity from the selected unit' do
    gram = ItemUnit.create!(unit_name: 'grams', item_symbol: 'g', unit_type: :weight, equivalent: 1)
    category = Category.create!(category_name: 'Herbs', default_unit: gram, kind: :produce)

    size = CategorySize.create!(category: category, item_unit: gram, quantity: 100, price: 5)

    expect(size.quantity_canonical.to_f).to eq(100.0)
    expect(size.canonical_unit_type).to eq('weight')
  end

  it 'keeps discrete quantity as its canonical quantity' do
    bunch = ItemUnit.create!(unit_name: 'bunch', item_symbol: 'bunch', unit_type: :discrete)
    category = Category.create!(category_name: 'Herbs', default_unit: bunch, kind: :produce)

    size = CategorySize.create!(category: category, item_unit: bunch, quantity: 1, price: 4)

    expect(size.quantity_canonical.to_f).to eq(1.0)
    expect(size.canonical_unit_type).to eq('discrete')
  end
end
