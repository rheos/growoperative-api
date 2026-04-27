require 'rails_helper'

# Narrow spec: when Foaf::Shadow#mirror_payment is called with a tx_row and
# both FOAF calls succeed, the row gets foaf_operation_id + foaf_posted_at.
# On failure (either FOAF call returns nil), the row stays unposted.
RSpec.describe Foaf::Shadow, type: :model, skip_hooks: true do
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
  let(:tx_row) do
    trustline.trustline_transactions.create!(
      amount: 10, description: 'test', transaction_type: 'payment',
      initiated_by: alice, balance_after: 10, foaf_direction: 'sent',
      foaf_posted_at: nil,
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

  describe '#mirror_payment with tx_row' do
    it 'writes foaf_operation_id + foaf_posted_at on successful confirm' do
      allow(fake_client).to receive(:create_pending_transfer).and_return({ 'id' => 42 })
      allow(fake_client).to receive(:confirm_transfer).and_return({
        'status' => 'confirmed', 'operation' => 999, 'totalFees' => 0.0,
      })

      Foaf::Shadow.new.mirror_payment(trustline, 10, alice, bob, tx_row: tx_row)

      tx_row.reload
      expect(tx_row.foaf_operation_id).to eq(999)
      expect(tx_row.foaf_posted_at).to be_within(5.seconds).of(Time.current)
    end

    it 'leaves tx_row unposted when create_pending_transfer fails' do
      allow(fake_client).to receive(:create_pending_transfer).and_return(nil)

      Foaf::Shadow.new.mirror_payment(trustline, 10, alice, bob, tx_row: tx_row)

      tx_row.reload
      expect(tx_row.foaf_operation_id).to be_nil
      expect(tx_row.foaf_posted_at).to be_nil
    end

    it 'leaves tx_row unposted when confirm_transfer fails' do
      allow(fake_client).to receive(:create_pending_transfer).and_return({ 'id' => 42 })
      allow(fake_client).to receive(:confirm_transfer).and_return(nil)

      Foaf::Shadow.new.mirror_payment(trustline, 10, alice, bob, tx_row: tx_row)

      tx_row.reload
      expect(tx_row.foaf_operation_id).to be_nil
      expect(tx_row.foaf_posted_at).to be_nil
    end

    it 'does not raise when tx_row is nil (hook-free call path)' do
      allow(fake_client).to receive(:create_pending_transfer).and_return({ 'id' => 42 })
      allow(fake_client).to receive(:confirm_transfer).and_return({ 'operation' => 1 })

      expect {
        Foaf::Shadow.new.mirror_payment(trustline, 10, alice, bob, tx_row: nil)
      }.not_to raise_error
    end
  end
end
