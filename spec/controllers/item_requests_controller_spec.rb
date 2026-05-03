require 'rails_helper'

RSpec.describe Api::V1::ItemRequestsController, type: :controller, skip_hooks: true do
  let(:barry)  { User.create!(user_name: 'barry',  password: 'password123') }
  let(:bruce)  { User.create!(user_name: 'bruce',  password: 'password123') }
  let(:bob)    { User.create!(user_name: 'bob',    password: 'password123') }
  let(:dianna) { User.create!(user_name: 'dianna', password: 'password123') }
  let(:john)   { User.create!(user_name: 'john',   password: 'password123') }

  let(:grade)     { Grade.create!(name: 'A', value: 30) }
  let(:item_unit) { ItemUnit.create!(unit_name: 'pounds', item_symbol: 'lb', unit_type: :weight, equivalent: 453.592) }
  let(:category)  { Category.create!(category_name: 'greens', default_unit: item_unit, kind: :produce, default_node_price: 1.0) }
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
    DatabaseCleaner.clean_with(:truncation)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(barry)
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

  describe '#request_chain_prices' do
    it 'compounds percent and flat markups from producer outward' do
      rel_one = Relationship.create!(user: dianna, friend: bob, status: :accepted)
      rel_two = Relationship.create!(user: bob, friend: barry, status: :accepted)
      inventory.update!(apply_first_hop_markup: true)
      UserRelationshipPrice.create!(
        user: dianna,
        friend: bob,
        category: category,
        relationship: rel_one,
        price: 15,
        price_type: 'percent'
      )
      UserRelationshipPrice.create!(
        user: bob,
        friend: barry,
        category: category,
        relationship: rel_two,
        price: 2,
        price_type: 'flat'
      )

      expect(controller.send(:request_chain_prices, inventory, [barry.id, bob.id, dianna.id])).to eq([5.75, 7.75])
    end

    it 'does not apply owner markup when first-hop markup is off' do
      rel_one = Relationship.create!(user: dianna, friend: bob, status: :accepted)
      rel_two = Relationship.create!(user: bob, friend: barry, status: :accepted)
      inventory.item.update!(producer_id: bruce.id)
      inventory.update!(apply_first_hop_markup: false)
      UserRelationshipPrice.create!(
        user: dianna,
        friend: bob,
        category: category,
        relationship: rel_one,
        price: 15,
        price_type: 'percent'
      )
      UserRelationshipPrice.create!(
        user: bob,
        friend: barry,
        category: category,
        relationship: rel_two,
        price: 2,
        price_type: 'flat'
      )

      expect(controller.send(:request_chain_prices, inventory, [barry.id, bob.id, dianna.id])).to eq([5.0, 7.0])
    end
  end

  describe 'POST #create' do
    it 'stores compounded per-hop prices on the created request chain' do
      allow(controller).to receive(:current_user).and_return(john)
      inventory.update!(price: 4, apply_first_hop_markup: false)

      rel_one = Relationship.create!(user: dianna, friend: bob, status: :accepted)
      rel_two = Relationship.create!(user: bob, friend: bruce, status: :accepted)
      rel_three = Relationship.create!(user: bruce, friend: barry, status: :accepted)
      rel_four = Relationship.create!(user: barry, friend: john, status: :accepted)

      UserRelationshipPrice.create!(
        user: bob,
        friend: bruce,
        category: category,
        relationship: rel_two,
        price: 5,
        price_type: 'percent'
      )
      UserRelationshipPrice.create!(
        user: bruce,
        friend: barry,
        category: category,
        relationship: rel_three,
        price: 0.5,
        price_type: 'flat'
      )
      UserRelationshipPrice.create!(
        user: barry,
        friend: john,
        category: category,
        relationship: rel_four,
        price: 20,
        price_type: 'percent'
      )

      expect(controller.send(:request_chain_prices, inventory, [john.id, barry.id, bruce.id, bob.id, dianna.id])).to eq([4.0, 4.2, 4.7, 5.65])

      post :create, params: { item_id: inventory.id, request: { quantity: 2 } }

      expect(response).to have_http_status(:ok)
      contract = RequestContract.find(JSON.parse(response.body).dig('data', 'contract_id'))
      expect(contract.user).to eq(john)
      expect(contract.item_requests.order(:step).map { |r| [r.user.user_name, r.friend.user_name, r.price.to_f] }).to eq([
        ['bob', 'dianna', 4.0],
        ['bruce', 'bob', 4.2],
        ['barry', 'bruce', 4.7],
        ['john', 'barry', 5.65],
      ])
    end
  end

  describe 'POST #reserve' do
    it 'uses the owner-entered reserve price in reserved dashboard payloads' do
      allow(controller).to receive(:current_user).and_return(bruce)
      listing_item = Item.create!(
        user: bruce,
        category: category,
        item_name: item_name,
        grade: grade,
        item_unit: item_unit,
        name: 'Egg Incubator',
        price: 225,
        quantity: 1
      )
      listing = Inventory.create!(
        user: bruce,
        item: listing_item,
        quantity: 1,
        price: 225,
        status: :available
      )
      Relationship.create!(
        user: bruce,
        friend: bob,
        status: :accepted,
        user_label: 'Alex',
        friend_label: 'Bruce'
      )

      post :reserve, params: {
        inventory_id: listing.id,
        user_id: bob.id,
        quantity: 1,
        price: 200
      }

      expect(response).to have_http_status(:ok)
      request = ItemRequest.last
      reserved_inventory = request.inventory
      expect(request.price.to_f).to eq(200.0)
      expect(request.request_contract.status).to eq('pending')
      expect(reserved_inventory.price.to_f).to eq(200.0)

      get :reserved

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      reserved_item = payload['data'].find { |group| group.is_a?(Hash) }.dig('items', 0)
      order = payload['data'].find { |group| group.is_a?(Hash) }['order']
      expect(order['is_ready']).to eq(false)
      expect(reserved_item['attributes']['total-price'].to_f).to eq(200.0)
      expect(reserved_item['attributes']['expected-price'].to_f).to eq(200.0)
      expect(reserved_item['attributes']['target-user-name']).to eq('Alex')
    end

    it 'marks seller-created reserved offers as actionable for the buyer' do
      allow(controller).to receive(:current_user).and_return(bruce)
      listing_item = Item.create!(
        user: bruce,
        category: category,
        item_name: item_name,
        grade: grade,
        item_unit: item_unit,
        name: 'Egg Incubator',
        price: 225,
        quantity: 1
      )
      listing = Inventory.create!(
        user: bruce,
        item: listing_item,
        quantity: 1,
        price: 225,
        status: :available
      )

      post :reserve, params: {
        inventory_id: listing.id,
        user_id: bob.id,
        quantity: 1,
        price: 200
      }

      expect(response).to have_http_status(:ok)
      allow(controller).to receive(:current_user).and_return(bob)

      get :requested

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(response.body)
      item = payload['data'].find { |group| group.is_a?(Hash) }.dig('items', 0)
      expect(item['attributes']['action-request']).to eq(true)
    end
  end

  describe 'POST #accept' do
    it 'returns a 4xx when the requested unit cannot be converted' do
      allow(controller).to receive(:current_user).and_return(dianna)
      bunch = ItemUnit.create!(unit_name: 'bunch', item_symbol: 'bunch', unit_type: :discrete)
      contract = RequestContract.create!(
        user: barry,
        item: item,
        inventory_id: inventory.id,
        quantity: 1,
        steps: 1,
        unit: bunch.id
      )
      request = ItemRequest.create!(
        user: barry,
        friend: dianna,
        request_contract: contract,
        price: 5,
        status: :pending,
        step: 1,
        sent: true
      )

      post :accept, params: { id: request.id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to eq('unit_conversion_mismatch')
      expect(request.reload).to be_pending
    end
  end
end
