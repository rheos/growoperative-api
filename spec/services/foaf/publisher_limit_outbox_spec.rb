require "rails_helper"

RSpec.describe Foaf::Publisher, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(
      user_name: "alice",
      password: "password123",
      foaf_address: "0x" + "aa" * 20
    )
  end
  let(:bob) do
    User.create!(
      user_name: "bob",
      password: "password123",
      foaf_address: "0x" + "bb" * 20
    )
  end
  let(:trustline) do
    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 10,
      credit_limit_b_to_a: 20,
      current_balance: 0
    )
  end
  let(:outbox_entry) do
    FoafOutboxEntry.latest_trustline_update_for(trustline)
  end
  let(:fake_client) { instance_double(Foaf::Client) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks)
      .and_return([{ "address" => "0xnetwork" }])
    allow(Foaf::Signer).to receive(:ensure_keypair!)
    allow(Foaf::Signer).to receive(:address_for) { |user| user.foaf_address }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it "publishes the snapshotted limits in both perspectives and marks posted" do
    expect(fake_client).to receive(:update_trustline).ordered.with(
      network_address: "0xnetwork",
      creditor_address: alice.foaf_address,
      debtor_address: bob.foaf_address,
      creditline_given: 20,
      creditline_received: 10
    ).and_return(success)
    expect(fake_client).to receive(:update_trustline).ordered.with(
      network_address: "0xnetwork",
      creditor_address: bob.foaf_address,
      debtor_address: alice.foaf_address,
      creditline_given: 10,
      creditline_received: 20
    ).and_return(success)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: outbox_entry
    )

    expect(outbox_entry.reload).to have_attributes(
      foaf_write_state: "posted",
      foaf_write_error: nil
    )
    expect(outbox_entry.foaf_posted_at).to be_present
  end

  it "uses the durable snapshot instead of a later in-memory trustline value" do
    entry = outbox_entry
    trustline.update_columns(
      credit_limit_a_to_b: 999,
      credit_limit_b_to_a: 888
    )

    expect(fake_client).to receive(:update_trustline).ordered.with(
      hash_including(
        creditline_given: 20,
        creditline_received: 10
      )
    ).and_return(success)
    expect(fake_client).to receive(:update_trustline).ordered.with(
      hash_including(
        creditline_given: 10,
        creditline_received: 20
      )
    ).and_return(success)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: entry
    )

    expect(entry.reload.foaf_write_state).to eq("posted")
  end

  it "retains an ambiguous accept for replay" do
    allow(fake_client).to receive(:update_trustline)
      .and_return(success, ambiguous)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: outbox_entry
    )

    expect(outbox_entry.reload).to have_attributes(
      foaf_write_state: "ambiguous_accept",
      foaf_posted_at: nil
    )
    expect(outbox_entry.foaf_write_error).to include("timeout")
  end

  it "records a definitive shared-write rejection" do
    allow(fake_client).to receive(:update_trustline).and_return(rejected)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: outbox_entry
    )

    expect(outbox_entry.reload).to have_attributes(
      foaf_write_state: "rejected",
      foaf_posted_at: nil
    )
  end

  it "does not publish a snapshot that was already superseded" do
    stale_entry = outbox_entry
    trustline.update!(credit_limit_a_to_b: 30)
    expect(fake_client).not_to receive(:update_trustline)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: stale_entry
    )

    expect(stale_entry.reload.foaf_write_state).to eq("superseded")
  end

  it "re-publishes the newest snapshot if an in-flight update is superseded" do
    stale_entry = outbox_entry
    calls = 0
    allow(fake_client).to receive(:update_trustline) do
      calls += 1
      trustline.update!(credit_limit_a_to_b: 30) if calls == 2
      success
    end

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: stale_entry
    )

    latest = FoafOutboxEntry.latest_trustline_update_for(trustline)
    expect(calls).to eq(4)
    expect(stale_entry.reload.foaf_write_state).to eq("superseded")
    expect(latest).to be_nil
    expect(
      trustline.foaf_outbox_entries.order(:id).last
    ).to have_attributes(
      credit_limit_a_to_b: 30,
      foaf_write_state: "posted"
    )
  end

  def success
    {
      "ok" => true,
      "status" => 201,
      "outcome" => "success",
      "body" => '{"action":"accepted"}'
    }
  end

  def ambiguous
    {
      "ok" => false,
      "status" => 503,
      "outcome" => "ambiguous",
      "body" => nil,
      "error" => "timeout"
    }
  end

  def rejected
    {
      "ok" => false,
      "status" => 422,
      "outcome" => "rejected",
      "body" => '{"error":"invalid limits"}',
      "error" => "invalid limits"
    }
  end
end
