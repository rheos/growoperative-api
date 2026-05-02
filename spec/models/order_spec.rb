require 'rails_helper'

RSpec.describe Order, type: :model do
  # Shared setup — creates buyer, seller, category, grade, item, and inventory
  # used across all examples.
  def create_test_data
    buyer = User.create!(
      email: 'buyer@example.com',
      password: 'password123',
      user_name: 'buyer',
    )
    seller = User.create!(
      email: 'seller@example.com',
      password: 'password123',
      user_name: 'seller',
    )
    item_unit = ItemUnit.find_or_create_by!(item_symbol: 'lb') do |unit|
      unit.unit_name = 'pounds'
      unit.unit_type = :weight
      unit.equivalent = 453.592
    end
    category = Category.create!(
      category_name: 'Vegetables',
      default_unit: item_unit,
      kind: :produce,
      default_node_price: 0,
    )
    grade = Grade.create!(name: 'A', value: '1')
    item = Item.create!(
      user: seller,
      category: category,
      grade: grade,
      item_unit: item_unit,
      quantity: 10,
      name: 'Lettuce',
      price: 5,
      date_available: Time.current,
      organic: false,
      avatars: [],
    )
    inventory = item.inventory.first
    { buyer: buyer, seller: seller, item: item, inventory: inventory, category: category, grade: grade }
  end

  def create_order_with_request(buyer, seller, inventory, status: :pending, price: 5, quantity: 2)
    order = Order.create!(
      user_id: buyer.id,
      friend_id: seller.id,
      order_label: 'Order test',
      order_status: status,
    )
    contract = RequestContract.create!(
      user: buyer,
      item: inventory.item,
      inventory_id: inventory.id,
      quantity: quantity,
      status: :accepted,
      steps: 1,
      current_step: 1,
    )
    request = ItemRequest.create!(
      user: buyer,
      friend: seller,
      request_contract: contract,
      order_id: order.id,
      price: price,
      status: :accepted,
    )
    { order: order, contract: contract, request: request }
  end

  describe '#settlement_amount' do
    it 'sums item request price times request contract quantity' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory], price: 6, quantity: 2)
      order = result[:order]

      contract_two = RequestContract.create!(
        user: data[:buyer],
        item: data[:item],
        inventory_id: data[:inventory].id,
        quantity: 1,
        status: :accepted,
        steps: 1,
        current_step: 1,
      )
      ItemRequest.create!(
        user: data[:buyer],
        friend: data[:seller],
        request_contract: contract_two,
        order_id: order.id,
        price: 5,
        status: :accepted,
      )

      expect(order.send(:settlement_amount).to_f).to eq(17.0)
    end
  end

  describe '#apply_action ship' do
    it 'ships all item requests and updates order status atomically' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])
      order = result[:order]

      order.apply_action({ action_name: 'ship' }, data[:seller].id.to_s)
      order.reload
      result[:request].reload

      expect(order.order_status).to eq('shipped')
      expect(order.shipped_on).to be_present
      expect(result[:request].shipped_at).to be_present
      expect(result[:request].status).to eq('completed')
    end

    it 'rejects ship when user is not the seller' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])

      ret = result[:order].apply_action({ action_name: 'ship' }, data[:buyer].id.to_s)
      expect(ret).to eq(false)
      expect(result[:order].reload.order_status).to eq('pending')
    end

    it 'rejects ship when order is already shipped' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory], status: :shipped)

      ret = result[:order].apply_action({ action_name: 'ship' }, data[:seller].id.to_s)
      expect(ret).to eq(false)
    end

    it 'ships with settlement type when provided' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])

      result[:order].apply_action(
        { action_name: 'ship', settlement_type: 'credit' },
        data[:seller].id.to_s,
      )
      result[:order].reload

      expect(result[:order].order_status).to eq('shipped')
      expect(result[:order].settlement_type).to eq('credit')
      expect(result[:order].settlement_status).to eq('proposed')
    end
  end

  describe '#apply_action add_item' do
    it 'rejects adding items to a shipped order' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory], status: :shipped)

      ret = result[:order].apply_action(
        { action_name: 'add_item', item_id: data[:inventory].id },
        data[:seller].id.to_s,
      )
      expect(ret).to eq(false)
    end

    it 'rejects adding items to an order with completed requests' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])

      # Mark the existing request as completed (simulating a shipped item)
      result[:request].update!(status: :completed, shipped_at: DateTime.now)

      ret = result[:order].apply_action(
        { action_name: 'add_item', item_id: data[:inventory].id },
        data[:seller].id.to_s,
      )
      expect(ret).to eq(false)
    end
  end

  describe '.find_or_create_pending' do
    it 'returns existing pending order when no items are completed' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])

      found = Order.find_or_create_pending(data[:buyer].id, data[:seller].id)
      expect(found.id).to eq(result[:order].id)
    end

    it 'creates a new order when existing pending order has completed requests' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory])

      # Simulate: item was shipped individually, order stayed pending
      result[:request].update!(status: :completed, shipped_at: DateTime.now)

      found = Order.find_or_create_pending(data[:buyer].id, data[:seller].id)
      expect(found.id).not_to eq(result[:order].id)
      expect(found.order_status).to eq('pending')
      expect(found.order_label).to start_with('Order ')
    end

    it 'creates a new order when no pending orders exist' do
      data = create_test_data

      found = Order.find_or_create_pending(data[:buyer].id, data[:seller].id)
      expect(found).to be_persisted
      expect(found.order_status).to eq('pending')
    end

    it 'skips shipped orders entirely' do
      data = create_test_data
      result = create_order_with_request(data[:buyer], data[:seller], data[:inventory], status: :shipped)

      found = Order.find_or_create_pending(data[:buyer].id, data[:seller].id)
      expect(found.id).not_to eq(result[:order].id)
    end
  end
end
