require "rails_helper"

RSpec.describe Foaf::Publisher, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(
      user_name: "publisher-kill-switch-alice",
      password: "password123",
      foaf_address: "0x#{'aa' * 20}"
    )
  end
  let(:bob) do
    User.create!(
      user_name: "publisher-kill-switch-bob",
      password: "password123",
      foaf_address: "0x#{'bb' * 20}"
    )
  end
  let(:trustline) do
    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 100,
      credit_limit_b_to_a: 100,
      current_balance: 0
    )
  end
  let(:tx_row) do
    trustline.trustline_transactions.create!(
      amount: 10,
      description: "test",
      transaction_type: "payment",
      initiated_by: alice,
      balance_after: 10,
      foaf_direction: "sent",
      foaf_posted_at: nil
    )
  end
  let(:fake_client) { instance_double(Foaf::Client) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  it "leaves a payment row buffered without touching FOAF" do
    expect(fake_client).not_to receive(:networks)
    expect(fake_client).not_to receive(:create_pending_transfer)
    expect(fake_client).not_to receive(:confirm_transfer)
    expect(Foaf::Signer).not_to receive(:ensure_keypair!)

    described_class.new.publish_payment(
      trustline,
      10,
      alice,
      bob,
      tx_row: tx_row
    )

    expect(tx_row.reload).to have_attributes(
      foaf_operation_id: nil,
      foaf_pending_transfer_id: nil,
      foaf_posted_at: nil,
      foaf_write_state: nil
    )
  end

  it "leaves a trustline-limit snapshot buffered without touching FOAF" do
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    expect(fake_client).not_to receive(:networks)
    expect(fake_client).not_to receive(:update_trustline)
    expect(Foaf::Signer).not_to receive(:ensure_keypair!)

    described_class.new.publish_trustline_update(
      trustline,
      alice,
      outbox_entry: entry
    )

    expect(entry.reload).to have_attributes(
      foaf_write_state: "pending",
      foaf_posted_at: nil,
      superseded_at: nil
    )
  end

  it "is also a no-op for a hook-free call without a buffer row" do
    expect(fake_client).not_to receive(:networks)
    expect(fake_client).not_to receive(:create_pending_transfer)

    expect do
      described_class.new.publish_payment(
        trustline,
        10,
        alice,
        bob,
        tx_row: nil
      )
    end.not_to raise_error
  end
end
