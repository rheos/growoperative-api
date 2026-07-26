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

  describe 'GET #summary' do
    let(:viewer) do
      User.create!(
        user_name: 'summary-viewer',
        email: 'summary-viewer@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000d01'
      )
    end

    before do
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(viewer)
    end

    it 'serves all balance aggregates from the single FOAF-backed summary' do
      expect(Foaf::BalanceSummary).to receive(:fetch).once.with(viewer).and_return(
        total_trustlines: 2,
        total_credit_owed: 30.to_d,
        total_credit_owed_to_me: 45.to_d,
        net_credit_position: 15.to_d,
        available_credit: 175.to_d
      )

      get :summary

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include(
        'total_trustlines' => 2,
        'total_credit_owed' => 30.0,
        'total_credit_owed_to_me' => 45.0,
        'net_credit_position' => 15.0,
        'available_credit' => 175.0
      )
      expect(JSON.parse(response.body)).not_to have_key('recent_transactions')
    end

    it 'returns 503 and never calls Rails balance aggregates when FOAF is unavailable' do
      allow(Foaf::BalanceSummary).to receive(:fetch).with(viewer).and_return(nil)
      expect(viewer).not_to receive(:total_credit_owed)
      expect(viewer).not_to receive(:total_credit_owed_to_me)
      expect(viewer).not_to receive(:net_credit_position)
      expect(viewer).not_to receive(:available_credit_total)

      get :summary

      expect(response).to have_http_status(:service_unavailable)
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
