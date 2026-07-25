require 'rails_helper'

RSpec.describe Foaf::ReplayWorker, type: :model, skip_hooks: true do
  let(:alice) do
    User.create!(user_name: 'alice', password: 'password123',
                 foaf_address: '0x' + 'aa' * 20)
  end
  let(:bob) do
    User.create!(user_name: 'bob', password: 'password123',
                 foaf_address: '0x' + 'bb' * 20)
  end
  let(:trustline) do
    Trustline.create!(
      user_a: alice, user_b: bob,
      credit_limit_a_to_b: 100, credit_limit_b_to_a: 100, current_balance: 0
    )
  end
  let(:fake_client) { instance_double(Foaf::Client) }

  before do
    allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(true)
    allow(Foaf::Config).to receive(:shared_writes?).and_return(false)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
    allow(Foaf::Signer).to receive(:ensure_keypair!)
    allow(Foaf::Signer).to receive(:address_for) { |u| u.foaf_address }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def unposted_tx(direction:, initiator: alice, amount: 10)
    mark_limit_updates_posted!
    trustline.trustline_transactions.create!(
      amount: amount, description: 'test', transaction_type: 'payment',
      initiated_by: initiator, balance_after: amount,
      foaf_direction: direction, foaf_posted_at: nil,
    )
  end

  def mark_limit_updates_posted!
    trustline
    FoafOutboxEntry.update_all(
      foaf_posted_at: Time.current,
      foaf_write_state: "posted"
    )
  end

  describe '.run' do
    it 'skips when FOAF publishing is disabled' do
      allow(Foaf::Config).to receive(:foaf_write_enabled?).and_return(false)
      expect(described_class.run).to eq(skipped: 'foaf_write_disabled')
    end

    it 'posts sent-direction rows via create_pending_transfer + confirm' do
      tx = unposted_tx(direction: 'sent')
      allow(fake_client).to receive(:create_pending_transfer).and_return({ 'id' => 1 })
      allow(fake_client).to receive(:confirm_transfer).and_return({ 'operation' => 77 })

      results = described_class.run

      expect(results).to include(attempted: 1, posted: 1, still_unposted: 0)
      expect(tx.reload.foaf_operation_id).to eq(77)
      expect(tx.reload.foaf_posted_at).not_to be_nil
    end

    it 'replays a retained trustline-limit update before balance writes' do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      tx = trustline.trustline_transactions.create!(
        amount: 10, description: 'test', transaction_type: 'payment',
        initiated_by: alice, balance_after: 10,
        foaf_direction: 'sent', foaf_posted_at: nil,
      )

      expect(fake_client).to receive(:update_trustline).ordered.twice
        .and_return({ 'action' => 'accepted' })
      expect(fake_client).to receive(:create_pending_transfer).ordered
        .and_return({ 'id' => 1 })
      expect(fake_client).to receive(:confirm_transfer).ordered
        .and_return({ 'operation' => 77 })

      results = described_class.run

      expect(entry.reload.foaf_posted_at).to be_present
      expect(tx.reload.foaf_posted_at).to be_present
      expect(results).to include(
        attempted: 2,
        posted: 2,
        limit_attempted: 1,
        limit_posted: 1
      )
    end

    it 'retains a failed trustline-limit update and posts it on a later replay' do
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      allow(fake_client).to receive(:update_trustline).and_return(
        nil,
        { 'action' => 'proposed' },
        { 'action' => 'accepted' }
      )

      failed_results = described_class.run

      expect(entry.reload).to have_attributes(
        foaf_write_state: 'ambiguous_proposal',
        foaf_posted_at: nil
      )
      expect(failed_results).to include(
        attempted: 1,
        posted: 0,
        still_unposted: 1,
        limit_still_unposted: 1
      )

      replayed_results = described_class.run

      expect(entry.reload).to have_attributes(
        foaf_write_state: 'posted'
      )
      expect(entry.foaf_posted_at).to be_present
      expect(replayed_results).to include(
        attempted: 1,
        posted: 1,
        still_unposted: 0,
        limit_posted: 1
      )
    end

    it 'does not automatically retry a definitive limit rejection' do
      allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
      entry = FoafOutboxEntry.latest_trustline_update_for(trustline)
      entry.update!(foaf_write_state: 'rejected')
      expect(fake_client).not_to receive(:update_trustline)

      results = described_class.run

      expect(results).to include(
        attempted: 0,
        skipped: 1,
        limit_skipped: 1
      )
      expect(entry.reload.foaf_posted_at).to be_nil
    end

    it 'posts received-direction rows by swapping sender/receiver (publish_settlement)' do
      tx = unposted_tx(direction: 'received')
      sent_args = nil
      allow(fake_client).to receive(:create_pending_transfer) do |args|
        sent_args = args
        { 'id' => 1 }
      end
      allow(fake_client).to receive(:confirm_transfer).and_return({ 'operation' => 88 })

      described_class.run

      # Initiator was alice; settlement = reverse direction, so FOAF from=bob.
      expect(sent_args[:from_address]).to eq(bob.foaf_address)
      expect(sent_args[:to_address]).to eq(alice.foaf_address)
      expect(tx.reload.foaf_operation_id).to eq(88)
    end

    it 'leaves row unposted when FOAF is down' do
      tx = unposted_tx(direction: 'sent')
      allow(fake_client).to receive(:create_pending_transfer).and_return(nil)

      results = described_class.run

      expect(results).to include(attempted: 1, posted: 0, still_unposted: 1)
      expect(tx.reload.foaf_posted_at).to be_nil
    end

    it 'skips rows with nil foaf_direction (historical / no-direction rows)' do
      mark_limit_updates_posted!
      trustline.trustline_transactions.create!(
        amount: 5, transaction_type: 'payment', initiated_by: alice,
        balance_after: 5, foaf_direction: nil, foaf_posted_at: nil,
      )
      expect(fake_client).not_to receive(:create_pending_transfer)

      results = described_class.run

      # filtered out by the where.not(foaf_direction: nil) — not even attempted
      expect(results).to include(attempted: 0, posted: 0)
    end

    it 'skips rows that are already posted' do
      mark_limit_updates_posted!
      trustline.trustline_transactions.create!(
        amount: 5, transaction_type: 'payment', initiated_by: alice,
        balance_after: 5, foaf_direction: 'sent',
        foaf_posted_at: 1.minute.ago, foaf_operation_id: 123,
      )
      expect(fake_client).not_to receive(:create_pending_transfer)

      results = described_class.run
      expect(results[:attempted]).to eq(0)
    end

    it 'does not automatically retry a definitive shared-write rejection' do
      allow(Foaf::Config).to receive(:shared_writes?).and_return(true)
      tx = unposted_tx(direction: 'sent')
      tx.update!(foaf_write_state: 'rejected')
      expect(fake_client).not_to receive(:create_pending_transfer)
      expect(fake_client).not_to receive(:confirm_transfer)
      expect(fake_client).not_to receive(:pending_transfer)
      expect(fake_client).not_to receive(:pending_transfer_by_idempotency_key)

      results = described_class.run

      expect(results).to include(attempted: 0, skipped: 1)
      expect(tx.reload.foaf_posted_at).to be_nil
    end
  end
end
