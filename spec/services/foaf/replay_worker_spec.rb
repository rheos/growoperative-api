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
    allow(Foaf::Config).to receive(:shadow_mode?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
    allow(Foaf::Signer).to receive(:ensure_keypair!)
    allow(Foaf::Signer).to receive(:address_for) { |u| u.foaf_address }
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def unposted_tx(direction:, initiator: alice, amount: 10)
    trustline.trustline_transactions.create!(
      amount: amount, description: 'test', transaction_type: 'payment',
      initiated_by: initiator, balance_after: amount,
      foaf_direction: direction, foaf_posted_at: nil,
    )
  end

  describe '.run' do
    it 'skips when shadow mode is off' do
      allow(Foaf::Config).to receive(:shadow_mode?).and_return(false)
      expect(described_class.run).to eq(skipped: 'shadow_mode_off')
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

    it 'posts received-direction rows by swapping sender/receiver (mirror_settlement)' do
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
      trustline.trustline_transactions.create!(
        amount: 5, transaction_type: 'payment', initiated_by: alice,
        balance_after: 5, foaf_direction: 'sent',
        foaf_posted_at: 1.minute.ago, foaf_operation_id: 123,
      )
      expect(fake_client).not_to receive(:create_pending_transfer)

      results = described_class.run
      expect(results[:attempted]).to eq(0)
    end
  end
end
