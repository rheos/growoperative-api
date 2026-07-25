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
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
    entry.update!(foaf_write_state: "rejected")
    expect(publisher).not_to receive(:publish_trustline_update)

    described_class.after_trustline_save(trustline, alice)
  end
end
