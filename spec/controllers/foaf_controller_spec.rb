require "rails_helper"

RSpec.describe Api::V1::FoafController, type: :controller, skip_hooks: true do
  let(:viewer) do
    User.create!(
      user_name: "history-viewer",
      password: "password123",
      foaf_address: "0x#{'aa' * 20}"
    )
  end
  let(:counterparty) do
    User.create!(
      user_name: "history-counterparty",
      password: "password123",
      foaf_address: "0x#{'bb' * 20}"
    )
  end
  let(:trustline) do
    Trustline.create!(
      user_a: viewer,
      user_b: counterparty,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 999
    )
  end

  before do
    allow(controller).to receive(:authenticate!).and_return(true)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user).and_return(viewer)
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
  end

  after { DatabaseCleaner.clean_with(:truncation) }

  it "returns FOAF-folded running balances" do
    result = {
      rows: [
        {
          balance_before: 12.5,
          transaction: { id: 7, balance_after: 19.75 }
        }
      ]
    }
    allow(Foaf::AuditService).to receive(:events_for_trustline)
      .with(trustline, viewer: viewer)
      .and_return(result)

    get :trustline_events, params: { id: trustline.id }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("rows", 0, "balance_before")).to eq(12.5)
    expect(JSON.parse(response.body).dig("rows", 0, "transaction", "balance_after")).to eq(19.75)
  end

  it "returns 503 instead of an empty 200 when FOAF history is unavailable" do
    allow(Foaf::AuditService).to receive(:events_for_trustline)
      .with(trustline, viewer: viewer)
      .and_return(error: "Running balance unavailable — FOAF user events request failed")

    get :trustline_events, params: { id: trustline.id }

    expect(response).to have_http_status(:service_unavailable)
  end
end
