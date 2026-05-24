require 'rails_helper'

RSpec.describe InvariantsService do
  def setup_pair
    buyer = User.create!(email: 'inv_buyer@example.com', password: 'password123', user_name: 'inv_buyer')
    seller = User.create!(email: 'inv_seller@example.com', password: 'password123', user_name: 'inv_seller')
    item_unit = ItemUnit.find_or_create_by!(item_symbol: 'lb') do |u|
      u.unit_name = 'pounds'; u.unit_type = :weight; u.equivalent = 453.592
    end
    category = Category.create!(category_name: 'Veg', default_unit: item_unit, kind: :produce, default_node_price: 0)
    grade = Grade.create!(name: 'A', value: '1')
    item = Item.create!(user: seller, category: category, grade: grade, item_unit: item_unit,
                        quantity: 10, name: 'Lettuce', price: 5, date_available: Time.current,
                        organic: false, avatars: [])
    { buyer: buyer, seller: seller, inventory: item.inventory.first }
  end

  # Builds one order for the pair with a single request at the given statuses.
  def make_order(buyer, seller, inventory, order_status:, request_status:)
    order = Order.create!(user_id: buyer.id, friend_id: seller.id,
                          order_label: 'Order test', order_status: order_status)
    contract = RequestContract.create!(user: buyer, item: inventory.item, inventory_id: inventory.id,
                                       quantity: 1, status: :accepted, steps: 1, current_step: 1)
    ItemRequest.create!(user: buyer, friend: seller, request_contract: contract,
                        order_id: order.id, price: 5, status: request_status)
    order
  end

  def consolidation_violations
    InvariantsService.run[:violations].select { |v| v[:name] == :order_consolidation }
  end

  describe 'order_consolidation invariant' do
    it 'flags two open pending orders for the same buyer-seller pair' do
      d = setup_pair
      o1 = make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :accepted)
      o2 = make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :accepted)

      violations = consolidation_violations
      expect(violations.size).to eq(1)
      expect(violations.first[:context][:order_ids]).to contain_exactly(o1.id, o2.id)
    end

    it 'passes when both requests are consolidated onto one pending order' do
      d = setup_pair
      order = make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :accepted)
      contract = RequestContract.create!(user: d[:buyer], item: d[:inventory].item, inventory_id: d[:inventory].id,
                                         quantity: 1, status: :accepted, steps: 1, current_step: 1)
      ItemRequest.create!(user: d[:buyer], friend: d[:seller], request_contract: contract,
                          order_id: order.id, price: 5, status: :accepted)

      expect(consolidation_violations).to be_empty
    end

    it 'ignores a shipped order alongside a new pending one (atomic-order rule)' do
      d = setup_pair
      make_order(d[:buyer], d[:seller], d[:inventory], order_status: :shipped, request_status: :completed)
      make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :accepted)

      expect(consolidation_violations).to be_empty
    end

    it 'ignores a pending order that already holds a completed request' do
      d = setup_pair
      # A pending order with a completed request is closed to new items, so a
      # second pending order beside it is expected, not a violation.
      make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :completed)
      make_order(d[:buyer], d[:seller], d[:inventory], order_status: :pending, request_status: :accepted)

      expect(consolidation_violations).to be_empty
    end
  end
end
