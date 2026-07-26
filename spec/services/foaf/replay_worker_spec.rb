require "rails_helper"

RSpec.describe Foaf::ReplayWorker, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(
      user_name: "replay-alice",
      password: "password123",
      foaf_address: "0x#{'aa' * 20}"
    )
  end
  let(:bob) do
    User.create!(
      user_name: "replay-bob",
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
  let(:publisher) { instance_double(Foaf::Publisher) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
    allow(Foaf::Publisher).to receive(:new).and_return(publisher)
  end

  after do
    DatabaseCleaner.clean_with(:truncation)
  end

  def unposted_tx(direction:, initiator: alice, amount: 10)
    mark_limit_updates_posted!
    trustline.trustline_transactions.create!(
      amount: amount,
      description: "test",
      transaction_type: "payment",
      initiated_by: initiator,
      balance_after: amount,
      foaf_direction: direction,
      foaf_posted_at: nil
    )
  end

  def mark_limit_updates_posted!
    trustline
    FoafOutboxEntry.update_all(
      foaf_posted_at: Time.current,
      foaf_write_state: "posted"
    )
  end

  describe ".run" do
    it "skips when FOAF publishing is disabled" do
      allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
      expect(Foaf::Publisher).not_to receive(:new)

      expect(described_class.run).to eq(skipped: "foaf_write_disabled")
    end

    it "leaves payment and limit rows buffered while the kill switch is off" do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      tx = trustline.trustline_transactions.create!(
        amount: 10,
        description: "test",
        transaction_type: "payment",
        initiated_by: alice,
        balance_after: 10,
        foaf_direction: "sent",
        foaf_posted_at: nil
      )
      allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
      expect(Foaf::Publisher).not_to receive(:new)

      expect(described_class.run).to eq(
        skipped: "shared_writes_disabled",
        buffered_payments: 1,
        buffered_limit_updates: 1
      )
      expect(tx.reload.foaf_posted_at).to be_nil
      expect(entry.reload.foaf_posted_at).to be_nil
    end

    it "replays sent-direction rows through the Publisher gem path" do
      tx = unposted_tx(direction: "sent")
      expect(publisher).to receive(:publish_payment) do |tl, amount, from, to, **kwargs|
        expect([tl, amount, from, to]).to eq([trustline, 10, alice, bob])
        expect(kwargs).to include(
          description: "test",
          operation: "payment",
          tx_row: tx
        )
        tx.update!(
          foaf_operation_id: 77,
          foaf_posted_at: Time.current,
          foaf_write_state: "posted"
        )
      end

      results = described_class.run

      expect(results).to include(attempted: 1, posted: 1, still_unposted: 0)
      expect(tx.reload.foaf_operation_id).to eq(77)
    end

    it "replays a retained trustline-limit update before balance writes" do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      tx = trustline.trustline_transactions.create!(
        amount: 10,
        description: "test",
        transaction_type: "payment",
        initiated_by: alice,
        balance_after: 10,
        foaf_direction: "sent",
        foaf_posted_at: nil
      )

      expect(publisher).to receive(:publish_trustline_update).ordered do
        entry.update!(
          foaf_posted_at: Time.current,
          foaf_write_state: "posted"
        )
      end
      expect(publisher).to receive(:publish_payment).ordered do
        tx.update!(
          foaf_operation_id: 78,
          foaf_posted_at: Time.current,
          foaf_write_state: "posted"
        )
      end

      results = described_class.run

      expect(results).to include(
        attempted: 2,
        posted: 2,
        limit_attempted: 1,
        limit_posted: 1
      )
    end

    it "retains a failed trustline-limit update and posts it on a later replay" do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      calls = 0
      expect(publisher).to receive(:publish_trustline_update).twice do
        calls += 1
        if calls == 2
          entry.update!(
            foaf_posted_at: Time.current,
            foaf_write_state: "posted"
          )
        end
      end

      failed_results = described_class.run
      expect(failed_results).to include(
        attempted: 1,
        posted: 0,
        limit_still_unposted: 1
      )

      replayed_results = described_class.run
      expect(replayed_results).to include(
        attempted: 1,
        posted: 1,
        limit_posted: 1
      )
      expect(entry.reload.foaf_posted_at).to be_present
    end

    it "does not automatically retry a definitive limit rejection" do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      entry.update!(foaf_write_state: "rejected")
      expect(publisher).not_to receive(:publish_trustline_update)

      results = described_class.run

      expect(results).to include(
        attempted: 0,
        skipped: 1,
        limit_skipped: 1
      )
      expect(entry.reload.foaf_posted_at).to be_nil
    end

    it "replays received-direction rows as settlements" do
      tx = unposted_tx(direction: "received")
      expect(publisher).to receive(:publish_settlement) do |tl, amount, payer, payee, **kwargs|
        expect([tl, amount, payer, payee]).to eq([trustline, 10, alice, bob])
        expect(kwargs).to include(tx_row: tx)
        tx.update!(
          foaf_operation_id: 88,
          foaf_posted_at: Time.current,
          foaf_write_state: "posted"
        )
      end

      described_class.run

      expect(tx.reload.foaf_operation_id).to eq(88)
    end

    it "leaves a row unposted when Publisher cannot resolve it" do
      tx = unposted_tx(direction: "sent")
      expect(publisher).to receive(:publish_payment)

      results = described_class.run

      expect(results).to include(attempted: 1, posted: 0, still_unposted: 1)
      expect(tx.reload.foaf_posted_at).to be_nil
    end

    it "filters historical rows with no FOAF direction" do
      mark_limit_updates_posted!
      trustline.trustline_transactions.create!(
        amount: 5,
        transaction_type: "payment",
        initiated_by: alice,
        balance_after: 5,
        foaf_direction: nil,
        foaf_posted_at: nil
      )
      expect(publisher).not_to receive(:publish_payment)

      expect(described_class.run).to include(attempted: 0, posted: 0)
    end

    it "skips rows that are already posted" do
      mark_limit_updates_posted!
      trustline.trustline_transactions.create!(
        amount: 5,
        transaction_type: "payment",
        initiated_by: alice,
        balance_after: 5,
        foaf_direction: "sent",
        foaf_posted_at: 1.minute.ago,
        foaf_operation_id: 123
      )
      expect(publisher).not_to receive(:publish_payment)

      expect(described_class.run[:attempted]).to eq(0)
    end

    it "does not automatically retry a definitive payment rejection" do
      tx = unposted_tx(direction: "sent")
      tx.update!(foaf_write_state: "rejected")
      expect(publisher).not_to receive(:publish_payment)

      results = described_class.run

      expect(results).to include(attempted: 0, skipped: 1)
      expect(tx.reload.foaf_posted_at).to be_nil
    end
  end
end
