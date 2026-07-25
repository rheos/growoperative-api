require "rails_helper"

RSpec.describe FoafOutboxEntry, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(user_name: "alice", password: "password123")
  end
  let(:bob) do
    User.create!(user_name: "bob", password: "password123")
  end

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  it "snapshots trustline limits in the same save" do
    trustline = Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 12.34,
      credit_limit_b_to_a: 56.78,
      current_balance: 0
    )

    entry = described_class.latest_trustline_update_for(trustline)

    expect(entry).to be_present
    expect(entry.credit_limit_a_to_b).to eq(12.34)
    expect(entry.credit_limit_b_to_a).to eq(56.78)
    expect(entry.foaf_write_state).to eq("pending")
    expect(entry.foaf_posted_at).to be_nil
  end

  it "supersedes an older unposted snapshot when limits change again" do
    trustline = Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 10,
      credit_limit_b_to_a: 20,
      current_balance: 0
    )
    original = described_class.latest_trustline_update_for(trustline)

    trustline.update!(credit_limit_a_to_b: 30)

    expect(original.reload).to have_attributes(
      foaf_write_state: "superseded",
      foaf_posted_at: nil
    )
    expect(original.superseded_at).to be_present
    expect(described_class.latest_trustline_update_for(trustline))
      .to have_attributes(
        credit_limit_a_to_b: 30,
        credit_limit_b_to_a: 20
      )
  end

  it "does not enqueue a limit update for a balance-only save" do
    trustline = Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 10,
      credit_limit_b_to_a: 20,
      current_balance: 0
    )
    original_count = trustline.foaf_outbox_entries.count

    trustline.update!(current_balance: 5)

    expect(trustline.foaf_outbox_entries.count).to eq(original_count)
  end

  it "rolls the outbox entry back when the trustline save rolls back" do
    expect do
      Trustline.transaction do
        Trustline.create!(
          user_a: alice,
          user_b: bob,
          credit_limit_a_to_b: 10,
          credit_limit_b_to_a: 20,
          current_balance: 0
        )
        raise ActiveRecord::Rollback
      end
    end.not_to change(described_class, :count)
  end

  it "is a true no-op when FOAF publishing is disabled" do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)

    Trustline.create!(
      user_a: alice,
      user_b: bob,
      credit_limit_a_to_b: 10,
      credit_limit_b_to_a: 20,
      current_balance: 0
    )

    expect(described_class.count).to eq(0)
  end
end
