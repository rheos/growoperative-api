require 'rails_helper'

RSpec.describe Api::V1::TrustlinesController, type: :controller, skip_hooks: true do
  before do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean_with(:truncation)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe 'GET #index' do
    it "uses the viewer's relationship label for the counterparty name" do
      bruce = User.create!(
        user_name: 'bruce-trustline-label',
        email: 'bruce-trustline-label@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000b01'
      )
      alex = User.create!(
        user_name: 'alexandremayer22@gmail.com',
        email: 'alex-trustline-label@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000a01'
      )
      trustline = Trustline.create!(
        user_a: bruce,
        user_b: alex,
        credit_limit_a_to_b: 100,
        credit_limit_b_to_a: 225,
        current_balance: -128
      )
      Relationship.create!(
        user: bruce,
        friend: alex,
        status: :accepted,
        user_label: 'Alex',
        friend_label: 'Bruce'
      )

      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(bruce)
      allow(Foaf::BalanceReader).to receive(:fetch).with(bruce).and_return([
        {
          trustline: trustline,
          counterparty: alex,
          viewer_balance: -128.to_d,
          my_credit_limit: 100.to_d,
          their_credit_limit: 225.to_d
        }
      ])

      get :index

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig(0, 'other_user', 'name')).to eq('Alex')
    end
  end

  describe 'POST #record_debt' do
    let(:bruce) do
      User.create!(
        user_name: 'bruce-record-debt',
        email: 'bruce-record-debt@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000c01'
      )
    end
    let(:alex) do
      User.create!(
        user_name: 'alex-record-debt',
        email: 'alex-record-debt@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000c02'
      )
    end
    let!(:trustline) do
      Trustline.create!(
        user_a: bruce,
        user_b: alex,
        credit_limit_a_to_b: 100,
        credit_limit_b_to_a: 100,
        current_balance: 0
      )
    end

    before do
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(bruce)
      # Isolate the Rails behaviour — FOAF mirroring is exercised elsewhere.
      allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
    end

    it 'raises the debtor-side limit to cover the debt when consent is given' do
      post :record_debt, params: { id: trustline.id, amount: 675, raise_limit_to: 675 }

      expect(response).to have_http_status(:ok)
      trustline.reload
      # bruce is user_a, so the cap on what he can owe is credit_limit_a_to_b.
      expect(trustline.credit_limit_a_to_b.to_f).to eq(675.0)
      expect(trustline.current_balance.to_f).to eq(675.0)
    end

    it 'records the debt but leaves the limit untouched without consent' do
      post :record_debt, params: { id: trustline.id, amount: 675 }

      expect(response).to have_http_status(:ok)
      trustline.reload
      expect(trustline.credit_limit_a_to_b.to_f).to eq(100.0)
      expect(trustline.current_balance.to_f).to eq(675.0)
    end
  end
end
