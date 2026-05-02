require 'rails_helper'
require 'securerandom'

RSpec.describe ItemRequest, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def unit(symbol, unit_type:, equivalent: nil, name: symbol)
    ItemUnit.create!(
      unit_name: name,
      item_symbol: symbol,
      unit_type: unit_type,
      equivalent: equivalent
    )
  end

  def build_request(source_unit:, quantity: 10, request_quantity: 1, request_unit: nil, pack_contains_quantity: nil, pack_contains_unit: nil)
    seller = User.create!(user_name: "seller-#{SecureRandom.hex(3)}", password: 'password123')
    buyer = User.create!(user_name: "buyer-#{SecureRandom.hex(3)}", password: 'password123')
    category = Category.create!(category_name: "category-#{SecureRandom.hex(3)}", default_unit: source_unit, kind: :produce)
    grade = Grade.create!(name: "A-#{SecureRandom.hex(3)}", value: 30)
    item = Item.create!(
      user: seller,
      category: category,
      grade: grade,
      item_unit: source_unit,
      name: "Item #{SecureRandom.hex(3)}",
      price: 5,
      quantity: quantity,
      pack_contains_quantity: pack_contains_quantity,
      pack_contains_unit: pack_contains_unit
    )
    inventory = item.inventory.first
    contract = RequestContract.create!(
      user: buyer,
      item: item,
      inventory_id: inventory.id,
      quantity: request_quantity,
      steps: 1,
      unit: request_unit&.id
    )
    request = ItemRequest.create!(
      user: buyer,
      friend: seller,
      request_contract: contract,
      price: 5,
      status: :pending,
      step: 1,
      sent: true
    )

    { seller: seller, buyer: buyer, item: item, inventory: inventory, contract: contract, request: request }
  end

  it 'decrements same-unit inventory without conversion' do
    pound = unit('lb', name: 'pounds', unit_type: :weight, equivalent: 453.592)
    data = build_request(source_unit: pound, quantity: 10, request_quantity: 2)

    expect(data[:request].accept_request).to eq(true)

    expect(data[:inventory].reload.quantity).to eq(8)
    expect(data[:inventory].quantity_canonical.to_f).to be_within(0.001).of(3628.736)
  end

  it 'converts same-dimension requests through canonical quantity' do
    pound = unit('lb', name: 'pounds', unit_type: :weight, equivalent: 453.592)
    gram = unit('g', name: 'grams', unit_type: :weight, equivalent: 1)
    data = build_request(source_unit: pound, quantity: 10, request_quantity: 453.592, request_unit: gram)

    expect(data[:request].accept_request).to eq(true)

    expect(data[:inventory].reload.quantity.to_f).to be_within(0.001).of(9.0)
    reserved = data[:contract].reload.inventory
    expect(reserved.quantity.to_f).to be_within(0.001).of(453.592)
    expect(reserved.item.item_unit).to eq(gram)
  end

  it 'rejects cross-dimension conversion without accepting the request' do
    pound = unit('lb', name: 'pounds', unit_type: :weight, equivalent: 453.592)
    bunch = unit('bunch', unit_type: :discrete)
    data = build_request(source_unit: pound, quantity: 10, request_quantity: 1, request_unit: bunch)

    result = data[:request].accept_request

    expect(result[:error]).to eq('unit_conversion_mismatch')
    expect(data[:request].reload).to be_pending
    expect(data[:inventory].reload.quantity).to eq(10)
  end

  it 'requires discrete requests to use the same unit' do
    bunch = unit('bunch', unit_type: :discrete)
    each = unit('each', unit_type: :discrete)
    data = build_request(source_unit: bunch, quantity: 10, request_quantity: 1, request_unit: each)

    result = data[:request].accept_request

    expect(result[:error]).to eq('unit_conversion_mismatch')
    expect(data[:inventory].reload.quantity).to eq(10)
  end

  it 'keeps a weight pack in the purchased pack unit for optional later breakdown' do
    case_unit = unit('case', unit_type: :discrete)
    pound = unit('lb', name: 'pounds', unit_type: :weight, equivalent: 453.592)
    data = build_request(
      source_unit: case_unit,
      quantity: 3,
      request_quantity: 1,
      pack_contains_quantity: 20,
      pack_contains_unit: pound
    )

    expect(data[:request].accept_request).to eq(true)

    reserved = data[:contract].reload.inventory
    expect(reserved.quantity.to_f).to eq(1.0)
    expect(reserved.quantity_canonical.to_f).to eq(1.0)
    expect(reserved.canonical_unit_type).to eq('discrete')
    expect(reserved.item.item_unit).to eq(case_unit)
    expect(reserved.item.pack_contains_quantity.to_f).to eq(20.0)
    expect(reserved.item.pack_contains_unit).to eq(pound)
    expect(data[:inventory].reload.quantity).to eq(2)
  end

  it 'keeps a discrete pack in the purchased pack unit for optional later breakdown' do
    case_unit = unit('case', unit_type: :discrete)
    bottle = unit('bottle', unit_type: :discrete)
    data = build_request(
      source_unit: case_unit,
      quantity: 3,
      request_quantity: 1,
      pack_contains_quantity: 24,
      pack_contains_unit: bottle
    )

    expect(data[:request].accept_request).to eq(true)

    reserved = data[:contract].reload.inventory
    expect(reserved.quantity.to_f).to eq(1.0)
    expect(reserved.quantity_canonical.to_f).to eq(1.0)
    expect(reserved.canonical_unit_type).to eq('discrete')
    expect(reserved.item.item_unit).to eq(case_unit)
    expect(reserved.item.pack_contains_quantity.to_f).to eq(24.0)
    expect(reserved.item.pack_contains_unit).to eq(bottle)
  end
end
