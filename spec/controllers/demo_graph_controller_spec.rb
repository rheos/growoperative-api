require "rails_helper"

RSpec.describe "Demo graph API", type: :request, skip_hooks: true do
  after { DatabaseCleaner.clean_with(:truncation) }

  it "uses FOAF balances for demo trustline edges" do
    bob = User.create!(
      user_name: "bob",
      password: "password123",
      foaf_address: "0x#{'ab' * 20}"
    )
    bruce = User.create!(
      user_name: "bruce",
      password: "password123",
      foaf_address: "0x#{'cd' * 20}"
    )
    trustline = Trustline.create!(
      user_a: bob,
      user_b: bruce,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 999
    )
    expect(Foaf::GraphBalanceReader).to receive(:fetch).once.and_return(trustline.id => 23.75)

    get "/v1/demo/users"

    edge = JSON.parse(response.body)["edges"].find { |item| item["type"] == "trustline" }
    expect(response).to have_http_status(200)
    expect(edge["balance"]).to eq(23.75)
  end

  it "returns 503 instead of Rails graph balances when FOAF is unavailable" do
    allow(Foaf::GraphBalanceReader).to receive(:fetch).and_return(nil)

    get "/v1/demo/users"

    expect(response).to have_http_status(:service_unavailable)
  end
end
