require 'rails_helper'

# Increment 2 of variable-weight "buy a share" listings (meat).
#
# The thing under test is the promise that nobody is ever billed on an estimate:
# a share is claimed against a weight range, the seller records the real hanging
# weight, the order cannot ship until they have, and settlement bills the number
# off the scale.
RSpec.describe Order, type: :model, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def pound
    ItemUnit.find_or_create_by!(item_symbol: 'lb') do |unit|
      unit.unit_name = 'pounds'
      unit.unit_type = :weight
      unit.equivalent = 453.592
    end
  end

  def meat_item(seller, price: 10, on_the_rail_delta: 1.30)
    Item.create!(
      user: seller,
      category: Category.find_or_create_by!(category_name: 'Meat') { |c| c.default_unit = pound; c.kind = :produce },
      item_unit: pound,
      quantity: 2, # two shares available
      name: 'Beef side',
      price: price,
      pricing_basis: :per_weight,
      sale_unit_label: 'side',
      est_weight_min: 450,
      est_weight_max: 550,
      cut_yield_factor: 0.6,
      on_the_rail_available: true,
      on_the_rail_delta: on_the_rail_delta
    )
  end

  def produce_item(seller)
    Item.create!(
      user: seller,
      category: Category.find_or_create_by!(category_name: 'Vegetables') { |c| c.default_unit = pound; c.kind = :produce },
      item_unit: pound,
      quantity: 10,
      name: 'Lettuce',
      price: 5
    )
  end

  def users
    buyer = User.create!(user_name: 'buyer', password: 'password123')
    seller = User.create!(user_name: 'madrone', password: 'password123')
    [buyer, seller]
  end

  # One share claimed, priced per pound, not yet weighed.
  def claim(buyer, seller, item, shares: 1, rate: nil, on_the_rail: false)
    order = Order.create!(
      user_id: buyer.id.to_s,
      friend_id: seller.id.to_s,
      order_label: 'Order test',
      order_status: :pending
    )
    contract = RequestContract.create!(
      user: buyer,
      item: item,
      inventory_id: item.inventory.first.id,
      quantity: shares,
      status: :accepted,
      steps: 1,
      current_step: 1,
      on_the_rail: on_the_rail,
      estimated_weight: item.estimated_weight_for(shares)
    )
    request = ItemRequest.create!(
      user: buyer,
      friend: seller,
      request_contract: contract,
      order_id: order.id,
      price: rate || item.billed_rate(on_the_rail: on_the_rail),
      status: :accepted
    )
    { order: order, contract: contract, request: request }
  end

  describe 'claiming a share' do
    it 'books the midpoint of the advertised range as the estimate' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))

      # 450..550 -> 500
      expect(claimed[:contract].estimated_weight).to eq(BigDecimal('500'))
      expect(claimed[:contract].actual_weight).to be_nil
      expect(claimed[:contract]).to be_weight_pending
    end

    it 'scales the estimate by the number of shares claimed' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller), shares: 2)

      expect(claimed[:contract].estimated_weight).to eq(BigDecimal('1000'))
    end

    it 'takes the on-the-rail delta off the per-pound rate' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller), on_the_rail: true)

      expect(claimed[:request].price).to eq(BigDecimal('8.7'))
    end

    it 'leaves the rate alone when the buyer wants cut and wrap' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller), on_the_rail: false)

      expect(claimed[:request].price).to eq(BigDecimal('10'))
    end
  end

  describe 'the ship gate' do
    it 'refuses to ship a share that has never been weighed' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      order = claimed[:order]

      expect(order.apply_action({ action_name: 'ship' }, seller.id)).to be false
      expect(order.reload.order_status).to eq('pending')
    end

    it 'ships once the weight is recorded' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      order = claimed[:order]

      order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }] },
        seller.id
      )

      expect(order.reload.apply_action({ action_name: 'ship' }, seller.id)).to be_truthy
      expect(order.reload.order_status).to eq('shipped')
    end

    it 'does not gate a fixed-price order' do
      buyer, seller = users
      claimed = claim(buyer, seller, produce_item(seller), shares: 2, rate: 5)
      order = claimed[:order]

      expect(order).not_to be_weight_pending
      expect(order.apply_action({ action_name: 'ship' }, seller.id)).to be_truthy
    end
  end

  describe 'finalize_weight' do
    it 'records the weight and stamps when it happened' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))

      claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512.5 }] },
        seller.id
      )

      contract = claimed[:contract].reload
      expect(contract.actual_weight).to eq(BigDecimal('512.5'))
      expect(contract.weight_finalized_at).to be_present
      expect(contract).not_to be_weight_pending
    end

    it 'keeps the buyer out of it' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))

      result = claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }] },
        buyer.id
      )

      expect(result).to be false
      expect(claimed[:contract].reload.actual_weight).to be_nil
    end

    it 'refuses once the order has shipped' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      order = claimed[:order]

      order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }] },
        seller.id
      )
      order.reload.apply_action({ action_name: 'ship' }, seller.id)

      result = order.reload.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 900 }] },
        seller.id
      )

      expect(result).to be false
      expect(claimed[:contract].reload.actual_weight).to eq(BigDecimal('512'))
    end

    it 'refuses once the buyer has signed, before settlement runs' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      order = claimed[:order]

      order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }] },
        seller.id
      )
      order.reload.apply_action({ action_name: 'ship' }, seller.id)
      order.reload.apply_action({ action_name: 'sign' }, buyer.id)
      expect(order.reload.order_status).to eq('signed')
      billed = order.settlement_amount

      result = order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 900 }] },
        seller.id
      )

      expect(result).to be false
      expect(claimed[:contract].reload.actual_weight).to eq(BigDecimal('512'))
      expect(order.reload.settlement_amount).to eq(billed)
    end

    it 'rejects a weight of zero rather than settling for nothing' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))

      result = claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 0 }] },
        seller.id
      )

      expect(result).to be false
      expect(claimed[:contract].reload.actual_weight).to be_nil
    end

    it 'rejects a line that belongs to another order' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      other = claim(User.create!(user_name: 'other', password: 'password123'), seller, meat_item(seller))

      result = claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: other[:contract].id, actual_weight: 480 }] },
        seller.id
      )

      expect(result).to be false
      expect(other[:contract].reload.actual_weight).to be_nil
    end

    it 'leaves the order untouched when one line in a batch is bad' do
      buyer, seller = users
      item = meat_item(seller)
      claimed = claim(buyer, seller, item)
      second = RequestContract.create!(
        user: buyer, item: item, inventory_id: item.inventory.first.id,
        quantity: 1, status: :accepted, steps: 1, current_step: 1,
        estimated_weight: 500
      )
      ItemRequest.create!(
        user: buyer, friend: seller, request_contract: second,
        order_id: claimed[:order].id, price: 10, status: :accepted
      )

      result = claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [
            { request_contract_id: claimed[:contract].id, actual_weight: 512 },
            { request_contract_id: second.id, actual_weight: -5 }
          ] },
        seller.id
      )

      expect(result).to be false
      expect(claimed[:contract].reload.actual_weight).to be_nil
      expect(second.reload.actual_weight).to be_nil
    end
  end

  describe 'settlement' do
    it 'bills the actual weight, not the estimate' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))
      order = claimed[:order]

      order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }] },
        seller.id
      )

      # $10/lb on 512 lb of carcass, not on the 500 lb estimate and not on 1 share.
      expect(order.reload.settlement_amount).to eq(BigDecimal('5120'))
    end

    it 'bills the discounted rate when the share went out on the rail' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller), on_the_rail: true)
      order = claimed[:order]

      order.apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 500 }] },
        seller.id
      )

      # $8.70/lb on 500 lb
      expect(order.reload.settlement_amount).to eq(BigDecimal('4350'))
    end

    it 'counts an unweighed share as nothing, not as rate times share count' do
      buyer, seller = users
      claimed = claim(buyer, seller, meat_item(seller))

      # Not $10 (the per-pound rate x 1 share) — there is no honest number yet.
      expect(claimed[:order].settlement_amount).to eq(0)
      expect(claimed[:order]).to be_weight_pending
    end

    it 'still bills price times quantity for a fixed-price order' do
      buyer, seller = users
      claimed = claim(buyer, seller, produce_item(seller), shares: 3, rate: 5)

      expect(claimed[:order].settlement_amount).to eq(BigDecimal('15'))
    end

    it 'mixes a weighed share and a fixed-price line on one order' do
      buyer, seller = users
      meat = meat_item(seller)
      claimed = claim(buyer, seller, meat)
      veg = produce_item(seller)
      veg_contract = RequestContract.create!(
        user: buyer, item: veg, inventory_id: veg.inventory.first.id,
        quantity: 4, status: :accepted, steps: 1, current_step: 1
      )
      ItemRequest.create!(
        user: buyer, friend: seller, request_contract: veg_contract,
        order_id: claimed[:order].id, price: 5, status: :accepted
      )

      claimed[:order].apply_action(
        { action_name: 'finalize_weight',
          weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 500 }] },
        seller.id
      )

      # 500 lb x $10 + 4 x $5
      expect(claimed[:order].reload.settlement_amount).to eq(BigDecimal('5020'))
    end
  end

  describe RequestContract do
    it 'refuses a weight on a fixed-price line' do
      buyer, seller = users
      veg = produce_item(seller)
      contract = RequestContract.new(
        user: buyer, item: veg, inventory_id: veg.inventory.first.id,
        quantity: 1, status: :accepted, steps: 1, current_step: 1,
        actual_weight: 500
      )

      expect(contract).not_to be_valid
      expect(contract.errors[:actual_weight]).to include('only applies to variable-weight listings')
    end

    it 'reports the share count as the settlement quantity for fixed-price lines' do
      buyer, seller = users
      claimed = claim(buyer, seller, produce_item(seller), shares: 3, rate: 5)

      expect(claimed[:contract].settlement_quantity).to eq(3)
    end
  end
end
