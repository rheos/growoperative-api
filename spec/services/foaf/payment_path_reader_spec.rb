require "rails_helper"

RSpec.describe Foaf::PaymentPathReader, skip_hooks: true do
  before do
    DatabaseCleaner.strategy = :deletion
    DatabaseCleaner.clean_with(:truncation)
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  let(:sender) do
    User.create!(
      user_name: "path-sender",
      email: "path-sender@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000a21"
    )
  end
  let(:relay) do
    User.create!(
      user_name: "path-relay",
      email: "path-relay@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000b21"
    )
  end
  let(:receiver) do
    User.create!(
      user_name: "path-receiver",
      email: "path-receiver@example.com",
      password: "password123",
      foaf_address: "0x0000000000000000000000000000000000000c21"
    )
  end
  let(:client) { instance_double(Foaf::Client) }

  before do
    Trustline.create!(
      user_a: sender,
      user_b: relay,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 0
    )
    Trustline.create!(
      user_a: relay,
      user_b: receiver,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 0
    )
    allow(client).to receive(:networks).and_return([
      { "address" => "0x0000000000000000000000000000000000000d21" }
    ])
  end

  def fetch(amount: "12", max_hops: 5)
    described_class.fetch(
      from_user: sender,
      to_user: receiver,
      amount: amount,
      max_hops: max_hops,
      client: client
    )
  end

  it "maps FOAF's authoritative address path onto app users" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "25",
      "path" => [
        sender.foaf_address.upcase,
        relay.foaf_address,
        receiver.foaf_address
      ]
    )

    result = fetch

    expect(result).to be_available
    expect(result).to be_found
    expect(result.path).to eq([sender, relay, receiver])
    expect(result.capacity).to eq(BigDecimal("25"))
  end

  it "returns no path when FOAF capacity is below the requested amount" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "11",
      "path" => [sender.foaf_address, relay.foaf_address, receiver.foaf_address]
    )

    result = fetch(amount: "12")

    expect(result).to be_available
    expect(result).not_to be_found
  end

  it "honors the app's stricter max-hops request" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "25",
      "path" => [sender.foaf_address, relay.foaf_address, receiver.foaf_address]
    )

    result = fetch(max_hops: 1)

    expect(result).to be_available
    expect(result).not_to be_found
  end

  it "fails loud when an address cannot be mapped to app identity metadata" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "25",
      "path" => [
        sender.foaf_address,
        "0x0000000000000000000000000000000000000e21",
        receiver.foaf_address
      ]
    )

    result = fetch

    expect(result).not_to be_available
    expect(result.error).to eq(
      "FOAF path contains an unknown GrowOperative identity"
    )
  end

  it "reports an invalid max-hops input without raising" do
    result = fetch(max_hops: "not-a-number")

    expect(result).not_to be_available
    expect(result.error).to match(/Invalid FOAF path response/)
  end
end
