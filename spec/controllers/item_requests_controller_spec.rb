require 'rails_helper'

RSpec.describe Api::V1::ItemRequestsController, type: :controller, skip_hooks: true do
  let(:barry)  { User.create!(user_name: 'barry',  password: 'password123') }
  let(:bruce)  { User.create!(user_name: 'bruce',  password: 'password123') }
  let(:bob)    { User.create!(user_name: 'bob',    password: 'password123') }
  let(:dianna) { User.create!(user_name: 'dianna', password: 'password123') }

  let(:grade)     { Grade.create!(name: 'A', value: 30) }
  let(:category)  { Category.create!(category_name: 'greens', default_unit: 1, default_consumer_unit: 1, default_node_price: 1.0) }
  let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lbs') }
  let(:item_name) { ItemName.create!(name: 'Black Krim', category: category) }
  let(:item) do
    Item.create!(
      user: dianna,
      category: category,
      item_name: item_name,
      grade: grade,
      item_unit: item_unit,
      name: 'Black Krim',
      price: 5.0,
      quantity: 100
    )
  end
  let(:inventory) do
    Inventory.create!(user: dianna, item: item, quantity: 100, price: 5, status: :available)
  end
  let(:request_contract) do
    RequestContract.create!(user: barry, item: item, inventory_id: inventory.id, quantity: 10, steps: 3)
  end

  before(:each) do
    allow(controller).to receive(:authenticate_user!).and_return(true)
  end

  after(:each) do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe '#notify_request_chain!' do
    it 'creates per-hop notifications using the direct contact as actor' do
      ItemRequest.create!(
        user: barry,
        friend: bruce,
        request_contract: request_contract,
        price: 7,
        status: :pending,
        step: 3,
        sent: true
      )
      ItemRequest.create!(
        user: bruce,
        friend: bob,
        request_contract: request_contract,
        price: 6,
        status: :pending,
        step: 2,
        sent: false
      )
      ItemRequest.create!(
        user: bob,
        friend: dianna,
        request_contract: request_contract,
        price: 5,
        status: :pending,
        step: 1,
        sent: false
      )

      expect {
        controller.send(:notify_request_chain!, request_contract)
      }.to change(Notification, :count).by(3)

      expect(Notification.find_by(recipient: bruce)&.actor).to eq(barry)
      expect(Notification.find_by(recipient: bob)&.actor).to eq(bruce)
      expect(Notification.find_by(recipient: dianna)&.actor).to eq(bob)

      expect(Notification.find_by(recipient: bob)&.message).to eq('bruce requested Black Krim')
      expect(Notification.find_by(recipient: dianna)&.message).to eq('bob requested Black Krim')
    end
  end
end
