require "rails_helper"

RSpec.describe Api::V1::PendingPaymentsController, type: :controller, skip_hooks: true do
  before do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean_with(:truncation)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  describe "PUT #confirm" do
    let(:payer) do
      User.create!(
        user_name: "receipt-payer",
        email: "receipt-payer@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f01"
      )
    end

    let(:payee) do
      User.create!(
        user_name: "receipt-payee",
        email: "receipt-payee@example.com",
        password: "password123",
        foaf_address: "0x0000000000000000000000000000000000000f02"
      )
    end

    let(:trustline) do
      Trustline.create!(
        user_a: payer,
        user_b: payee,
        credit_limit_a_to_b: 100,
        credit_limit_b_to_a: 100,
        current_balance: 50
      )
    end

    let(:pending_payment) do
      PendingPayment.create!(
        from_user: payer,
        to_user: payee,
        trustline: trustline,
        amount: 10,
        kind: "payment"
      )
    end

    before do
      allow(controller).to receive(:authenticate!).and_return(true)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(payee)
      allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
      allow(Foaf::BalanceReader).to receive(:fetch).with(payee).and_return([
        {
          trustline: trustline,
          counterparty: payer,
          viewer_balance: -40.0,
          my_credit_limit: 100.0,
          their_credit_limit: 100.0
        }
      ])
      allow(Notifications).to receive(:publish!)
    end

    it "returns the buffered operation and FOAF refetch without a Rails balance" do
      put :confirm, params: { id: pending_payment.id }

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body).not_to have_key("new_balance")
      expect(body.dig("operation", "write_state")).to eq("buffered")
      expect(body.dig("foaf_state", "current_balance")).to eq(-40.0)
      expect(body.dig("pending_payment", "status")).to eq("confirmed")
      expect(pending_payment.reload).to be_confirmed
    end

    it "stores parsed Polygonscan metadata on the settlement row" do
      hash = "0x#{'ab' * 32}"
      url = "https://polygonscan.com/tx/#{hash}"
      pending_payment.update!(description: "USDT #{url}")

      put :confirm, params: { id: pending_payment.id }

      expect(response).to have_http_status(:accepted)
      tx = TrustlineTransaction.order(:id).last
      expect(tx.description).to eq("USDT #{url}")
      payment = tx.path_info.with_indifferent_access.fetch("external_payment")
      expect(payment["chain"]).to eq("polygon")
      expect(payment["tx_hash"]).to eq(hash)
      expect(payment["explorer_url"]).to eq(url)
    end
  end
end
