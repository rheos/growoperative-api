require 'rails_helper'

RSpec.describe Order, type: :model do
  describe '#settlement_amount' do
    it 'sums item request price times request contract quantity' do
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
      category = Category.create!(
        category_name: 'Vegetables',
        default_unit: 1,
        default_consumer_unit: 1,
        default_node_price: 0,
      )
      grade = Grade.create!(name: 'A', value: '1')
      item = Item.create!(
        user: seller,
        category: category,
        grade: grade,
        quantity: 10,
        name: 'Lettuce',
        price: 5,
        date_available: Time.current,
        organic: false,
        avatars: [],
      )
      inventory = item.inventory.first
      order = Order.create!(
        user_id: buyer.id,
        friend_id: seller.id,
        order_label: 'Order 1',
        order_status: :pending,
      )

      contract_one = RequestContract.create!(
        user: buyer,
        item: item,
        inventory_id: inventory.id,
        quantity: 2,
        status: :accepted,
        steps: 1,
        current_step: 1,
      )
      ItemRequest.create!(
        user: buyer,
        friend: seller,
        request_contract: contract_one,
        order_id: order.id,
        price: 6,
        status: :accepted,
      )

      contract_two = RequestContract.create!(
        user: buyer,
        item: item,
        inventory_id: inventory.id,
        quantity: 1,
        status: :accepted,
        steps: 1,
        current_step: 1,
      )
      ItemRequest.create!(
        user: buyer,
        friend: seller,
        request_contract: contract_two,
        order_id: order.id,
        price: 5,
        status: :accepted,
      )

      expect(order.send(:settlement_amount).to_f).to eq(17.0)
    end
  end
end
