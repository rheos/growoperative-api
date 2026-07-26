require "rails_helper"

RSpec.describe Foaf::DirectCapacityReader, skip_hooks: true do
  let(:sender) do
    instance_double(
      User,
      foaf_address: "0x0000000000000000000000000000000000000a01"
    )
  end
  let(:receiver) do
    instance_double(
      User,
      foaf_address: "0x0000000000000000000000000000000000000b01"
    )
  end
  let(:client) { instance_double(Foaf::Client) }

  before do
    allow(client).to receive(:networks).and_return([
      { "address" => "0x0000000000000000000000000000000000000c01" }
    ])
  end

  it "uses protocol capacity when FOAF returns the exact direct path" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "42.75",
      "path" => [sender.foaf_address.upcase, receiver.foaf_address]
    )

    result = described_class.fetch(
      from_user: sender,
      to_user: receiver,
      client: client
    )

    expect(result).to be_available
    expect(result.capacity).to eq(BigDecimal("42.75"))
    expect(result).to be_sufficient_for("42.75")
  end

  it "returns zero direct capacity when FOAF selects a routed path" do
    allow(client).to receive(:max_capacity_path_info).and_return(
      "capacity" => "100",
      "path" => [
        sender.foaf_address,
        "0x0000000000000000000000000000000000000d01",
        receiver.foaf_address
      ]
    )

    result = described_class.fetch(
      from_user: sender,
      to_user: receiver,
      client: client
    )

    expect(result).to be_available
    expect(result.capacity).to eq(BigDecimal("0"))
    expect(result).not_to be_sufficient_for("0.01")
  end

  it "fails loud when FOAF cannot return capacity" do
    allow(client).to receive(:max_capacity_path_info).and_return(nil)

    result = described_class.fetch(
      from_user: sender,
      to_user: receiver,
      client: client
    )

    expect(result).not_to be_available
    expect(result.error).to eq("FOAF capacity unavailable")
  end
end
