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

    it 'returns 503 without reading Rails balances when FOAF is unavailable' do
      viewer = User.create!(
        user_name: 'foaf-unavailable-viewer',
        email: 'foaf-unavailable-viewer@example.com',
        password: 'password123',
        foaf_address: '0x0000000000000000000000000000000000000a02'
      )
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(viewer)
      allow(Foaf::BalanceReader).to receive(:fetch).with(viewer).and_return(nil)
      expect(viewer).not_to receive(:trustlines)

      get :index

      expect(response).to have_http_status(:service_unavailable)
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
      allow(Foaf::BalanceReader).to receive(:fetch).with(bruce).and_return([
        {
          trustline: trustline,
          counterparty: alex,
          viewer_balance: 675.0,
          my_credit_limit: 675.0,
          their_credit_limit: 100.0
        }
      ])
    end

    it 'raises the debtor-side limit to cover the debt when consent is given' do
      post :record_debt, params: { id: trustline.id, amount: 675, raise_limit_to: 675 }

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body).not_to have_key("new_balance")
      expect(body).not_to have_key("trustline")
      expect(body.dig("operation", "write_state")).to eq("buffered")
      expect(body.dig("foaf_state", "current_balance")).to eq(675.0)
      trustline.reload
      # bruce is user_a, so the cap on what he can owe is credit_limit_a_to_b.
      expect(trustline.credit_limit_a_to_b.to_f).to eq(675.0)
      expect(trustline.current_balance.to_f).to eq(675.0)
    end

    it 'records the debt but leaves the limit untouched without consent' do
      post :record_debt, params: { id: trustline.id, amount: 675 }

      expect(response).to have_http_status(:accepted)
      trustline.reload
      expect(trustline.credit_limit_a_to_b.to_f).to eq(100.0)
      expect(trustline.current_balance.to_f).to eq(675.0)
    end
  end

  describe "POST #payment" do
    let(:payer) do
      User.create!(
        user_name: "foaf-capacity-payer",
        email: "foaf-capacity-payer@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f11"
      )
    end
    let(:payee) do
      User.create!(
        user_name: "foaf-capacity-payee",
        email: "foaf-capacity-payee@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f12"
      )
    end
    let!(:payment_trustline) do
      Trustline.create!(
        user_a: payer,
        user_b: payee,
        credit_limit_a_to_b: 5,
        credit_limit_b_to_a: 5,
        current_balance: 5
      )
    end

    before do
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(payer)
      allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
      allow(Foaf::BalanceReader).to receive(:fetch).with(payer).and_return([
        {
          trustline: payment_trustline,
          counterparty: payee,
          viewer_balance: 7.0,
          my_credit_limit: 20.0,
          their_credit_limit: 5.0
        }
      ])
    end

    it "admits from FOAF capacity and bypasses the Rails capacity helper" do
      result = Foaf::DirectCapacityReader::Result.new(
        capacity: BigDecimal("20")
      )
      allow(Foaf::DirectCapacityReader).to receive(:fetch)
        .with(from_user: payer, to_user: payee)
        .and_return(result)
      expect_any_instance_of(Trustline).not_to receive(:can_handle_payment?)

      post :payment, params: { id: payment_trustline.id, amount: 2 }

      expect(response).to have_http_status(:accepted)
      expect(payment_trustline.reload.current_balance.to_f).to eq(7.0)
      expect(JSON.parse(response.body).dig("operation", "write_state")).to eq("buffered")
    end

    it "rejects when FOAF reports insufficient direct capacity" do
      result = Foaf::DirectCapacityReader::Result.new(
        capacity: BigDecimal("1")
      )
      allow(Foaf::DirectCapacityReader).to receive(:fetch).and_return(result)

      expect do
        post :payment, params: { id: payment_trustline.id, amount: 2 }
      end.not_to change(TrustlineTransaction, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["errors"]).to eq(["Insufficient credit limit"])
    end

    it "returns 503 instead of falling back when FOAF capacity is unavailable" do
      result = Foaf::DirectCapacityReader::Result.new(
        capacity: BigDecimal("0"),
        error: "FOAF capacity unavailable"
      )
      allow(Foaf::DirectCapacityReader).to receive(:fetch).and_return(result)

      post :payment, params: { id: payment_trustline.id, amount: 2 }

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["capacity_error"]).to eq(
        "FOAF capacity unavailable"
      )
    end
  end

  describe "FOAF path endpoints" do
    let(:path_sender) do
      User.create!(
        user_name: "controller-path-sender",
        email: "controller-path-sender@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f21"
      )
    end
    let(:path_relay) do
      User.create!(
        user_name: "controller-path-relay",
        email: "controller-path-relay@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f22"
      )
    end
    let(:path_receiver) do
      User.create!(
        user_name: "controller-path-receiver",
        email: "controller-path-receiver@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f23"
      )
    end

    before do
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(path_sender)
    end

    it "returns the FOAF path and protocol-calculated capacity" do
      result = Foaf::PaymentPathReader::Result.new(
        path: [path_sender, path_relay, path_receiver],
        capacity: BigDecimal("20")
      )
      allow(Foaf::PaymentPathReader).to receive(:fetch).and_return(result)

      post :find_path, params: {
        to_user_id: path_receiver.id,
        amount: 12,
        max_hops: 3
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["path_found"]).to be(true)
      expect(body["path"].map { |user| user["id"] }).to eq(
        [path_sender.id, path_relay.id, path_receiver.id]
      )
      expect(body["capacity"]).to eq(20.0)
    end

    it "executes the FOAF-verified path without Rails capacity checks" do
      path = [path_sender, path_relay, path_receiver]
      tx_row = instance_double(TrustlineTransaction)
      result = Foaf::PaymentPathReader::Result.new(
        path: path,
        capacity: BigDecimal("20")
      )
      allow(Foaf::PaymentPathReader).to receive(:fetch).and_return(result)
      expect(Trustline).to receive(:execute_payment_path).with(
        path,
        12.0,
        description: "routed",
        originating_request: nil,
        capacity_verified_by_foaf: true
      ).and_return([tx_row])
      allow(Foaf::WriteReceipt).to receive(:operation_payload)
        .with(tx_row)
        .and_return(
          buffer_id: 41,
          write_state: "posted",
          foaf_operation_id: 81
        )
      allow(Foaf::BalanceReader).to receive(:fetch).with(path_sender).and_return([])

      post :execute_path_payment, params: {
        to_user_id: path_receiver.id,
        amount: 12,
        description: "routed",
        max_hops: 3
      }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to eq(
        "Path payment executed successfully"
      )
      expect(JSON.parse(response.body).dig("operations", 0, "write_state"))
        .to eq("posted")
    end

    it "returns 202 with per-hop state when any path write is ambiguous" do
      path = [path_sender, path_relay, path_receiver]
      tx_rows = [
        instance_double(TrustlineTransaction),
        instance_double(TrustlineTransaction)
      ]
      result = Foaf::PaymentPathReader::Result.new(
        path: path,
        capacity: BigDecimal("20")
      )
      allow(Foaf::PaymentPathReader).to receive(:fetch).and_return(result)
      allow(Trustline).to receive(:execute_payment_path).and_return(tx_rows)
      allow(Foaf::WriteReceipt).to receive(:operation_payload)
        .with(tx_rows[0])
        .and_return(buffer_id: 41, write_state: "posted")
      allow(Foaf::WriteReceipt).to receive(:operation_payload)
        .with(tx_rows[1])
        .and_return(buffer_id: 42, write_state: "ambiguous_confirm")
      allow(Foaf::BalanceReader).to receive(:fetch).with(path_sender).and_return([])

      post :execute_path_payment, params: {
        to_user_id: path_receiver.id,
        amount: 12
      }

      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["message"]).to eq(
        "Path payment buffered pending FOAF reconciliation"
      )
    end

    it "returns 422 with per-hop state when any path write is rejected" do
      path = [path_sender, path_relay, path_receiver]
      tx_row = instance_double(TrustlineTransaction)
      result = Foaf::PaymentPathReader::Result.new(
        path: path,
        capacity: BigDecimal("20")
      )
      allow(Foaf::PaymentPathReader).to receive(:fetch).and_return(result)
      allow(Trustline).to receive(:execute_payment_path).and_return([tx_row])
      allow(Foaf::WriteReceipt).to receive(:operation_payload)
        .with(tx_row)
        .and_return(buffer_id: 41, write_state: "rejected")
      allow(Foaf::BalanceReader).to receive(:fetch).with(path_sender).and_return([])

      post :execute_path_payment, params: {
        to_user_id: path_receiver.id,
        amount: 12
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["message"]).to eq(
        "FOAF rejected one or more path writes"
      )
    end

    it "returns 503 rather than using Rails BFS when FOAF pathfinding fails" do
      result = Foaf::PaymentPathReader::Result.new(
        path: nil,
        capacity: BigDecimal("0"),
        error: "FOAF path unavailable"
      )
      allow(Foaf::PaymentPathReader).to receive(:fetch).and_return(result)
      expect(Trustline).not_to receive(:execute_payment_path)

      post :execute_path_payment, params: {
        to_user_id: path_receiver.id,
        amount: 12
      }

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["path_error"]).to eq(
        "FOAF path unavailable"
      )
    end
  end
end
