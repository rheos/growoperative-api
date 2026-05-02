require 'rails_helper'

RSpec.describe CategoryUnit, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it 'prevents duplicate unit assignments for the same category' do
    unit = ItemUnit.create!(unit_name: 'each', item_symbol: 'each', unit_type: :discrete)
    category = Category.create!(category_name: 'Garden Equipment', default_unit: unit, kind: :goods)

    CategoryUnit.create!(category: category, item_unit: unit)
    duplicate = CategoryUnit.new(category: category, item_unit: unit)

    expect(duplicate).not_to be_valid
  end
end
