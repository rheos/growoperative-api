require "rails_helper"

RSpec.describe Foaf::LedgerHooks, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(user_name: "alice", password: "password123")
  end
  let(:bob) do
    User.create!(user_name: "bob", password: "password123")
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
  let(:publisher) { instance_double(Foaf::Publisher) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(described_class).to receive(:publisher).and_return(publisher)
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it "publishes the durable snapshot created by the trustline save" do
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    expect(publisher).to receive(:publish_trustline_update).with(
      trustline,
      alice,
      outbox_entry: entry
    )

    described_class.after_trustline_save(trustline, alice)
  end

  it "does not retry a definitive rejection while shared writes are active" do
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    entry.update!(foaf_write_state: "rejected")
    expect(publisher).not_to receive(:publish_trustline_update)

    described_class.after_trustline_save(trustline, alice)
  end

  it "leaves limit and balance operations buffered while the kill switch is off" do
    allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    tx_row = trustline.trustline_transactions.create!(
      amount: 10,
      transaction_type: "payment",
      initiated_by: alice,
      balance_after: 10,
      foaf_direction: "sent"
    )
    expect(publisher).not_to receive(:publish_trustline_update)
    expect(publisher).not_to receive(:publish_payment)
    expect(publisher).not_to receive(:publish_settlement)

    described_class.after_trustline_save(trustline, alice)
    described_class.after_payment(
      trustline,
      10,
      alice,
      bob,
      tx_row: tx_row
    )
    described_class.after_settlement(
      trustline,
      10,
      alice,
      bob,
      tx_row: tx_row
    )

    expect(entry.reload.foaf_posted_at).to be_nil
    expect(tx_row.reload.foaf_posted_at).to be_nil
  end
end
