require 'rails_helper'

# The HTTP contract for variable-weight (meat) shares.
#
# The model specs drive Order#apply_action with a plain hash, which bypasses
# strong params entirely. That is exactly where this feature can fail silently:
# if `weights` is not permitted in OrdersController#order_action_params, the
# array is dropped, `action[:weights]` comes back blank, apply_action returns
# false, and the seller gets a 422 with the model code sitting there working
# perfectly. These specs go through the real request stack so that cannot
# regress unnoticed.
RSpec.describe 'V1 meat share weight finalization', type: :request, skip_hooks: true do
  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  let(:buyer)  { User.create!(user_name: 'meat-buyer', password: 'bobsentme!') }
  let(:seller) { User.create!(user_name: 'madrone', password: 'bobsentme!') }

  def headers_for(user)
    { 'Authorization' => "Bearer #{JwtGenerationService.new(user).token}",
      'Content-Type' => 'application/json' }
  end

  def json
    JSON.parse(response.body)
  end

  let(:pound) do
    ItemUnit.find_or_create_by!(item_symbol: 'lb') do |unit|
      unit.unit_name = 'pounds'
      unit.unit_type = :weight
      unit.equivalent = 453.592
    end
  end

  let(:meat_item) do
    Item.create!(
      user: seller,
      category: Category.find_or_create_by!(category_name: 'Meat') { |c| c.default_unit = pound; c.kind = :produce },
      item_unit: pound,
      quantity: 2,
      name: 'Beef side',
      price: 10,
      pricing_basis: :per_weight,
      sale_unit_label: 'side',
      est_weight_min: 450,
      est_weight_max: 550,
      cut_yield_factor: 0.6,
      on_the_rail_available: true,
      on_the_rail_delta: 1.30
    )
  end

  # One claimed share, accepted, sitting on a pending order — the state a seller
  # is in when they walk to the scale.
  def claim_share(on_the_rail: false, shares: 1)
    order = Order.create!(
      user_id: buyer.id.to_s, friend_id: seller.id.to_s,
      order_label: 'Order test', order_status: :pending
    )
    contract = RequestContract.create!(
      user: buyer, item: meat_item, inventory_id: meat_item.inventory.first.id,
      quantity: shares, status: :accepted, steps: 1, current_step: 1,
      on_the_rail: on_the_rail,
      estimated_weight: meat_item.estimated_weight_for(shares)
    )
    request_row = ItemRequest.create!(
      user: buyer, friend: seller, request_contract: contract,
      order_id: order.id, price: meat_item.billed_rate(on_the_rail: on_the_rail),
      status: :accepted
    )
    { order: order, contract: contract, request: request_row }
  end

  def patch_action(order, body, user)
    patch "/v1/orders/#{order.id}",
          params: { order_action: body }.to_json,
          headers: headers_for(user)
  end

  # The app claims a share with `unit: null`, which routes a direct request
  # through the request-chain branch of ItemRequestsController#create rather
  # than the unit branch. On-the-rail has to be priced there too.
  describe 'POST /v1/items/:inventory_id/requests (claim, no unit)' do
    before do
      low, high = [buyer.id, seller.id].minmax
      Relationship.create!(user_id: low, friend_id: high, status: :accepted, action_user_id: buyer.id)
    end

    def claim_via_api(on_the_rail:)
      post "/v1/items/#{meat_item.inventory.first.id}/requests",
           params: { request: { quantity: 1, unit: nil, on_the_rail: on_the_rail } }.to_json,
           headers: headers_for(buyer)
      expect(response).to have_http_status(:ok)
      RequestContract.find(json.dig('data', 'contract_id'))
    end

    it 'bills the on-the-rail rate when the buyer takes the share on the rail' do
      contract = claim_via_api(on_the_rail: true)

      expect(contract.on_the_rail).to be true
      # $10/lb less the $1.30 on-the-rail delta.
      expect(contract.item_requests.first.price).to eq(BigDecimal('8.7'))
    end

    it 'bills the full rate for cut and wrap' do
      contract = claim_via_api(on_the_rail: false)

      expect(contract.on_the_rail).to be false
      expect(contract.item_requests.first.price).to eq(BigDecimal('10'))
    end
  end

  describe 'PATCH /v1/orders/:id finalize_weight' do
    it 'permits the weights array and records the scale reading' do
      claimed = claim_share

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512.5 }]
      }, seller)

      expect(response).to have_http_status(:ok)
      expect(claimed[:contract].reload.actual_weight).to eq(BigDecimal('512.5'))
      expect(claimed[:contract].weight_finalized_at).to be_present
    end

    it 'returns the weight state on the order payload the app reads' do
      claimed = claim_share

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 500 }]
      }, seller)

      expect(response).to have_http_status(:ok)
      data = json.fetch('data')
      expect(data['weight_pending']).to be false
      line = data.fetch('items').first
      expect(line['request_contract_id']).to eq(claimed[:contract].id)
      expect(line['pricing_basis']).to eq('per_weight')
      expect(line['actual_weight']).to eq(500.0)
      expect(line['sale_unit_label']).to eq('side')
      expect(line['weight_pending']).to be false
      # $10/lb on 500 lb of carcass — not $10 for one share.
      expect(data['settlement_amount'].to_f).to eq(5000.0)
    end

    it 'refuses a buyer trying to set their own price' do
      claimed = claim_share

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 1 }]
      }, buyer)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(claimed[:contract].reload.actual_weight).to be_nil
    end

    it 'refuses a non-positive weight' do
      claimed = claim_share

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 0 }]
      }, seller)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(claimed[:contract].reload.actual_weight).to be_nil
    end

    it 'refuses a contract that is not on this order' do
      claimed = claim_share
      other_buyer = User.create!(user_name: 'someone-else', password: 'bobsentme!')
      other = RequestContract.create!(
        user: other_buyer, item: meat_item, inventory_id: meat_item.inventory.first.id,
        quantity: 1, status: :accepted, steps: 1, current_step: 1, estimated_weight: 500
      )

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: other.id, actual_weight: 480 }]
      }, seller)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other.reload.actual_weight).to be_nil
    end
  end

  describe 'the ship gate over HTTP' do
    it 'refuses to ship an unweighed share and reports it on the payload' do
      claimed = claim_share

      # The app gates its own Ship button on this flag.
      get "/v1/orders/#{claimed[:order].id}", headers: headers_for(seller)
      expect(json.fetch('data')['weight_pending']).to be true

      patch_action(claimed[:order], { action_name: 'ship' }, seller)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(claimed[:order].reload.order_status).to eq('pending')
    end

    it 'ships once the weight is recorded' do
      claimed = claim_share

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }]
      }, seller)
      expect(response).to have_http_status(:ok)

      patch_action(claimed[:order], { action_name: 'ship' }, seller)

      expect(response).to have_http_status(:ok)
      expect(claimed[:order].reload.order_status).to eq('shipped')
    end

    it 'refuses to re-weigh after shipping' do
      claimed = claim_share
      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 512 }]
      }, seller)
      patch_action(claimed[:order], { action_name: 'ship' }, seller)
      expect(response).to have_http_status(:ok)

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 900 }]
      }, seller)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(claimed[:contract].reload.actual_weight).to eq(BigDecimal('512'))
    end
  end

  describe 'on-the-rail pricing through settlement' do
    it 'bills the discounted rate on the real weight' do
      claimed = claim_share(on_the_rail: true)
      expect(claimed[:request].price).to eq(BigDecimal('8.7'))

      patch_action(claimed[:order], {
        action_name: 'finalize_weight',
        weights: [{ request_contract_id: claimed[:contract].id, actual_weight: 500 }]
      }, seller)

      expect(response).to have_http_status(:ok)
      # $8.70/lb on 500 lb, not the $10 list rate.
      expect(json.fetch('data')['settlement_amount'].to_f).to eq(4350.0)
    end
  end

  describe 'fixed-price orders are untouched' do
    it 'still ships without any weight step' do
      veg = Item.create!(
        user: seller,
        category: Category.find_or_create_by!(category_name: 'Vegetables') { |c| c.default_unit = pound; c.kind = :produce },
        item_unit: pound, quantity: 10, name: 'Lettuce', price: 5
      )
      order = Order.create!(
        user_id: buyer.id.to_s, friend_id: seller.id.to_s,
        order_label: 'Veg order', order_status: :pending
      )
      contract = RequestContract.create!(
        user: buyer, item: veg, inventory_id: veg.inventory.first.id,
        quantity: 4, status: :accepted, steps: 1, current_step: 1
      )
      ItemRequest.create!(
        user: buyer, friend: seller, request_contract: contract,
        order_id: order.id, price: 5, status: :accepted
      )

      patch_action(order, { action_name: 'ship' }, seller)

      expect(response).to have_http_status(:ok)
      expect(order.reload.order_status).to eq('shipped')
      data = json.fetch('data')
      expect(data['weight_pending']).to be false
      expect(data['settlement_amount'].to_f).to eq(20.0)
    end
  end
end
