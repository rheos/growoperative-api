require "rails_helper"

RSpec.describe Foaf::GraphBalanceReader, skip_hooks: true do
  let!(:alice) do
    User.create!(
      user_name: "graph-alice",
      password: "password123",
      foaf_address: "0x#{'aa' * 20}"
    )
  end
  let!(:bob) do
    User.create!(
      user_name: "graph-bob",
      password: "password123",
      foaf_address: "0x#{'bb' * 20}"
    )
  end
  let!(:carol) do
    User.create!(
      user_name: "graph-carol",
      password: "password123",
      foaf_address: "0x#{'cc' * 20}"
    )
  end
  let!(:alice_bob) do
    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 999
    )
  end
  let!(:alice_carol) do
    Trustline.create!(
      user_a: alice,
      user_b: carol,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 888
    )
  end
  let(:client) { instance_double(Foaf::Client) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
    allow(Foaf::Client).to receive(:new).and_return(client)
    allow(client).to receive(:networks).and_return([{ "address" => "0xnetwork" }])
  end

  after { DatabaseCleaner.clean_with(:truncation) }

  it "fetches one FOAF trustline list per canonical user_a and ignores Rails balances" do
    expect(client).to receive(:user_trustlines).once.with(
      network_address: "0xnetwork",
      user_address: alice.foaf_address
    ).and_return([
      {
        "counterParty" => bob.foaf_address.upcase,
        "balance" => -12.5,
        "given" => 100,
        "received" => 100
      },
      {
        "counterParty" => carol.foaf_address,
        "balance" => 7.25,
        "given" => 100,
        "received" => 100
      }
    ])

    expect(described_class.fetch([alice_bob, alice_carol])).to eq(
      alice_bob.id => 12.5,
      alice_carol.id => -7.25
    )
  end

  it "returns nil when an edge is missing from FOAF instead of using Rails" do
    allow(client).to receive(:user_trustlines).and_return([])

    expect(described_class.fetch([alice_bob])).to be_nil
  end

  it "returns an empty map without touching FOAF when there are no edges" do
    expect(Foaf::Client).not_to receive(:new)

    expect(described_class.fetch([])).to eq({})
  end
end
