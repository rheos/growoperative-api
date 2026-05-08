require 'rails_helper'

RSpec.describe Foaf::AuditService, type: :model, skip_hooks: true do
  # Use the FOAF addresses to identify the canonical sides (user_a is the
  # smaller id, but the actual id ordering depends on DB auto-increment in
  # the test run, so we resolve via trustline.user_a / .user_b after create
  # rather than assuming alice == user_a).
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

  # The trustline-as-stored canonicalizes its sides. Resolve through it.
  let(:canonical_user_a) { trustline.user_a }
  let(:canonical_user_b) { trustline.user_b }
  let(:fake_client) { instance_double(Foaf::Client) }

  # Two FOAF Transfer events: canonical_user_a sends $50 to canonical_user_b,
  # then $30 more. Running balance ends at +80 in canonical (user_a) terms.
  def transfer(value:, block:, ts:)
    {
      'type'         => 'Transfer',
      'value'        => value,
      'direction'    => 'sent',
      'timestamp'    => ts,
      'blockNumber'  => block,
      'extraData'    => '{"app":"growoperative"}',
      'counterParty' => canonical_user_b.foaf_address,
    }
  end

  before do
    allow(Foaf::Config).to receive(:shadow_mode?).and_return(true)
    allow(Foaf::Client).to receive(:new).and_return(fake_client)
    allow(fake_client).to receive(:networks).and_return([{ 'address' => '0xnetwork' }])
    allow(fake_client).to receive(:user_events).and_return([
      transfer(value: 50.0, block: 101, ts: 1_000_000),
      transfer(value: 30.0, block: 102, ts: 1_000_100),
    ])
    allow(fake_client).to receive(:trustline_events).and_return([])
  end

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  describe '.events_for_trustline (viewer perspective)' do
    it 'returns canonical balances for the user_a viewer (no flip)' do
      result = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_a)
      # Endpoint returns rows in descending order (newest first).
      newest, oldest = result[:rows]

      expect(oldest[:transaction][:id]).to eq(101)
      expect(oldest[:balance_before]).to eq(0.0)
      expect(oldest[:transaction][:balance_after]).to eq(50.0)

      expect(newest[:transaction][:id]).to eq(102)
      expect(newest[:balance_before]).to eq(50.0)
      expect(newest[:transaction][:balance_after]).to eq(80.0)
    end

    it 'flips balances for the user_b viewer (negation)' do
      result = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_b)
      newest, oldest = result[:rows]

      # Same magnitudes, opposite signs — viewer-perspective for user_b means
      # "user_b is owed" = negative.
      expect(oldest[:balance_before]).to eq(0.0)
      expect(oldest[:transaction][:balance_after]).to eq(-50.0)

      expect(newest[:balance_before]).to eq(-50.0)
      expect(newest[:transaction][:balance_after]).to eq(-80.0)
    end

    it 'leaves tx.amount magnitudes untouched regardless of viewer' do
      from_a = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_a)
      from_b = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_b)

      a_amounts = from_a[:rows].map { |r| r[:transaction][:amount] }
      b_amounts = from_b[:rows].map { |r| r[:transaction][:amount] }
      expect(a_amounts).to eq([30.0, 50.0])
      expect(b_amounts).to eq([30.0, 50.0])
    end

    it 'attributes mirrored settlement transfers to the actual payer' do
      allow(fake_client).to receive(:user_events).and_return([
        {
          'type'         => 'Transfer',
          'value'        => 80.20,
          'direction'    => 'sent',
          'timestamp'    => 1_000_200,
          'blockNumber'  => 103,
          'extraData'    => {
            app: 'growoperative',
            operation: 'settlement',
            payment_request: {
              requested_by_name: canonical_user_a.user_name,
              paid_by_name: canonical_user_b.user_name,
              payee_name: canonical_user_a.user_name,
            },
            description: "Cash settlement from #{canonical_user_b.user_name} to #{canonical_user_a.user_name}",
          }.to_json,
          'counterParty' => canonical_user_b.foaf_address,
        },
      ])

      result = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_a)
      row = result[:rows].first

      expect(row[:transaction][:transaction_type]).to eq('settlement')
      expect(row[:transaction][:initiated_by_id]).to eq(canonical_user_b.id)
      expect(row[:transaction][:initiated_by_name]).to eq(canonical_user_b.user_name)
      expect(row[:transaction][:description]).to eq(
        "Cash settlement from #{canonical_user_b.user_name} to #{canonical_user_a.user_name}"
      )
      expect(row[:transaction][:path_info][:payment_request]["requested_by_name"]).to eq(canonical_user_a.user_name)
    end

    it 'recognizes legacy cash settlement descriptions without operation metadata' do
      allow(fake_client).to receive(:user_events).and_return([
        {
          'type'         => 'Transfer',
          'value'        => 80.20,
          'direction'    => 'sent',
          'timestamp'    => 1_000_200,
          'blockNumber'  => 104,
          'extraData'    => {
            app: 'growoperative',
            description: "Cash settlement from #{canonical_user_b.user_name} to #{canonical_user_a.user_name}",
          }.to_json,
          'counterParty' => canonical_user_b.foaf_address,
        },
      ])

      result = Foaf::AuditService.events_for_trustline(trustline, viewer: canonical_user_a)
      row = result[:rows].first

      expect(row[:transaction][:transaction_type]).to eq('settlement')
      expect(row[:transaction][:initiated_by_name]).to eq(canonical_user_b.user_name)
    end
  end
end
